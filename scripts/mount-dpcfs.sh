#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: mount_dpc.sh
# Description: Mounts DTFS on a list of remote hosts via SSH.
# Performs unmount of old paths first, then mounts the new path.
# Usage: ./mount_dpc.sh [ip_list_file]
# Env Vars: PARALLEL, RETRIES, REMOTE_MOUNTPOINT, REMOTE_UMOUNT_PATHS
# ==============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IP_LIST_FILE="${1:-$SCRIPT_DIR/df_ip_list.txt}"

# Configuration with defaults
PARALLEL="${PARALLEL:-16}"
RETRIES="${RETRIES:-3}"
REMOTE_MOUNTPOINT="${REMOTE_MOUNTPOINT:-/llm_workspace_1P}"
# Space-separated list of paths to unmount
REMOTE_UMOUNT_PATHS="${REMOTE_UMOUNT_PATHS:-/mnt/9w1N7vBPmO3wMAYjqZL /mnt/yWXKUIzKaqvtk0rLm /mnt/model_test /mnt/bigio /mnt/mpi_tools /mnt/case_test /mnt/c3_test}"
SSH_USER="${SSH_USER:-}"
SSH_PORT="${SSH_PORT:-}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-}"
SSH_MUX="${SSH_MUX:-1}"

# Help message
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0") [ip_list_file]"
    echo "Env: PARALLEL (default: 16)"
    echo "     RETRIES (default: 3)"
    echo "     REMOTE_MOUNTPOINT (default: /llm_workspace_1P)"
    echo "     REMOTE_UMOUNT_PATHS (default: list of old paths to unmount)"
    echo "     SSH_USER (default: current user)"
    echo "     SSH_PORT (default: ssh default)"
    echo "     SSH_IDENTITY_FILE (default: ssh default)"
    echo "     SSH_MUX (default: 1)"
    exit 0
fi

# Validation
if [[ ! -f "$IP_LIST_FILE" ]]; then
    echo "[ERROR] IP list file not found: $IP_LIST_FILE" >&2
    exit 1
fi

if [[ -z "$REMOTE_MOUNTPOINT" ]]; then
    echo "[ERROR] REMOTE_MOUNTPOINT is not set" >&2
    exit 1
fi

if [[ ! "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -le 0 ]]; then
    echo "[ERROR] PARALLEL must be a positive integer: $PARALLEL" >&2
    exit 1
fi

if [[ ! "$RETRIES" =~ ^[0-9]+$ ]] || [[ "$RETRIES" -le 0 ]]; then
    echo "[ERROR] RETRIES must be a positive integer: $RETRIES" >&2
    exit 1
fi

if [[ -n "$SSH_PORT" ]] && { [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -le 0 ]]; }; then
    echo "[ERROR] SSH_PORT must be a positive integer: $SSH_PORT" >&2
    exit 1
fi

if [[ -n "$SSH_IDENTITY_FILE" ]] && [[ ! -f "$SSH_IDENTITY_FILE" ]]; then
    echo "[ERROR] SSH_IDENTITY_FILE not found: $SSH_IDENTITY_FILE" >&2
    exit 1
fi

# Function to execute on remote host
run_host() {
    local ip="$1"
    local attempt=1
    local target="${SSH_USER:+${SSH_USER}@}${ip}"

    # SSH Options
    local ssh_opts=(
        -o BatchMode=yes
        -o ConnectTimeout=10
        -o ServerAliveInterval=10
        -o ServerAliveCountMax=3
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
    )
    if [[ "$SSH_MUX" != "0" ]]; then
        ssh_opts+=(-o ControlMaster=auto -o ControlPersist=60s -o "ControlPath=/tmp/k8scluster-ssh-%r@%h:%p")
    fi
    if [[ -n "$SSH_PORT" ]]; then
        ssh_opts+=(-p "$SSH_PORT")
    fi
    if [[ -n "$SSH_IDENTITY_FILE" ]]; then
        ssh_opts+=(-i "$SSH_IDENTITY_FILE")
    fi

    # Construct the remote command
    local cmd_umount=""
    local cmd_mount=""

    # 1. Unmount old paths (ignore errors if not mounted)
    if [[ -n "${REMOTE_UMOUNT_PATHS// }" ]]; then
        # Use 'for' loop on remote side to handle multiple paths
        cmd_umount="for p in $REMOTE_UMOUNT_PATHS; do echo \"[INFO] Unmounting \$p\"; umount -f \"\$p\" >/dev/null 2>&1 || true; done"
    fi

    # 2. Create directory and Mount
    # Check mkdir success before mounting
    cmd_mount="mkdir -p \"$REMOTE_MOUNTPOINT\" && mount -t dtfs \"$REMOTE_MOUNTPOINT\" \"$REMOTE_MOUNTPOINT\" && mount | grep -q \" $REMOTE_MOUNTPOINT \""

    if [[ -n "$cmd_umount" ]]; then
        local output
        if output=$(ssh "${ssh_opts[@]}" "$target" "$cmd_umount" 2>&1); then
            echo "$output" | sed "s/^/[$ip] /"
        else
            echo "$output" | sed "s/^/[$ip] [WARN] /"
        fi
    fi

    while [[ "$attempt" -le "$RETRIES" ]]; do
        local output

        if output=$(ssh "${ssh_opts[@]}" "$target" "$cmd_mount" 2>&1); then
            echo "$output" | sed "s/^/[$ip] /"
            echo "OK $ip"
            return 0
        fi

        echo "$output" | sed "s/^/[$ip] [FAIL] /"

        sleep "$attempt"
        attempt=$((attempt + 1))
    done

    echo "FAIL $ip"
    return 1
}

export -f run_host
export REMOTE_MOUNTPOINT REMOTE_UMOUNT_PATHS RETRIES SSH_USER SSH_PORT SSH_IDENTITY_FILE SSH_MUX

# Read IPs (ignoring comments and empty lines)
# Compatible with bash 3.2+ (macOS default) by using array assignment
OLD_IFS="$IFS"
IFS=$'\n'
ALL_IPS=($(awk 'NF && $1 !~ /^#/ {print $1}' "$IP_LIST_FILE" | sort -u))
IFS="$OLD_IFS"

if [[ "${#ALL_IPS[@]}" -eq 0 ]]; then
    echo "[ERROR] Empty IP list in: $IP_LIST_FILE" >&2
    exit 1
fi

echo ""
echo "[INFO] Mounting on ${#ALL_IPS[@]} hosts..."

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_IPS=()

while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == OK\ * ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [[ "$line" == FAIL\ * ]]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_IPS+=("${line#FAIL }")
    fi
done < <(printf '%s\n' "${ALL_IPS[@]}" | xargs -n 1 -P "$PARALLEL" bash -c 'run_host "$1"' _)

echo ""
echo "[INFO] Mount Summary: SUCCESS=$SUCCESS_COUNT, FAIL=$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
    echo "[ERROR] Failed hosts:" >&2
    printf '%s\n' "${FAILED_IPS[@]}" >&2
    exit 2
fi

echo "[INFO] All operations completed successfully."
exit 0
