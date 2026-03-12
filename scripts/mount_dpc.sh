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
    cmd_mount="mkdir -p \"$REMOTE_MOUNTPOINT\" && "
    cmd_mount+="echo \"[INFO] Mounting $REMOTE_MOUNTPOINT\" && "
    cmd_mount+="mount -t dtfs \"$REMOTE_MOUNTPOINT\" \"$REMOTE_MOUNTPOINT\""

    while [[ "$attempt" -le "$RETRIES" ]]; do
        local output

        # Execute Unmount (if needed)
        if [[ -n "$cmd_umount" ]]; then
            if output=$(ssh "${ssh_opts[@]}" "$target" "$cmd_umount" 2>&1); then
                echo "$output" | sed "s/^/[$ip] /"
            else
                # Unmount failure is usually ignored (or handled by || true inside), but if ssh fails we might want to log
                echo "$output" | sed "s/^/[$ip] [WARN] /"
            fi
        fi

        # Execute Mount
        if output=$(ssh "${ssh_opts[@]}" "$target" "$cmd_mount" 2>&1); then
            echo "$output" | sed "s/^/[$ip] /"
            echo "OK $ip"
            return 0
        fi

        echo "$output" | sed "s/^/[$ip] [FAIL] /"

        # Simple backoff
        sleep "$attempt"
        attempt=$((attempt + 1))
    done

    echo "FAIL $ip"
    return 1
}

# Function to verify mount status
check_mount() {
    local ip="$1"
    local target="${SSH_USER:+${SSH_USER}@}${ip}"
    local ssh_opts=(
        -o BatchMode=yes
        -o ConnectTimeout=10
        -o ServerAliveInterval=10
        -o ServerAliveCountMax=3
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
    )
    if [[ -n "$SSH_PORT" ]]; then
        ssh_opts+=(-p "$SSH_PORT")
    fi
    if [[ -n "$SSH_IDENTITY_FILE" ]]; then
        ssh_opts+=(-i "$SSH_IDENTITY_FILE")
    fi

    # Check if mountpoint exists in /proc/mounts or mount command output
    if ssh "${ssh_opts[@]}" "$target" "mount | grep -q \" $REMOTE_MOUNTPOINT \"" >/dev/null 2>&1; then
        echo "MOUNT_OK $ip"
        return 0
    else
        echo "MOUNT_FAIL $ip"
        return 1
    fi
}

export -f run_host check_mount
export REMOTE_MOUNTPOINT REMOTE_UMOUNT_PATHS RETRIES

# Function to check SSH connectivity
check_ssh() {
    local ip="$1"
    local target="${SSH_USER:+${SSH_USER}@}${ip}"
    local ssh_opts=(
        -o BatchMode=yes
        -o ConnectTimeout=5
        -o ServerAliveInterval=5
        -o ServerAliveCountMax=1
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
    )
    if [[ -n "$SSH_PORT" ]]; then
        ssh_opts+=(-p "$SSH_PORT")
    fi
    if [[ -n "$SSH_IDENTITY_FILE" ]]; then
        ssh_opts+=(-i "$SSH_IDENTITY_FILE")
    fi
    if ssh "${ssh_opts[@]}" "$target" "exit 0" >/dev/null 2>&1; then
        echo "SSH_OK $ip"
        return 0
    else
        echo "SSH_FAIL $ip"
        return 1
    fi
}
export -f check_ssh

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

echo "[INFO] Checking SSH connectivity for ${#ALL_IPS[@]} hosts..."

# Check SSH in parallel
exec 3>&1
SSH_CHECK_OUTPUT="$(
    printf '%s\n' "${ALL_IPS[@]}" | xargs -n 1 -P "$PARALLEL" bash -c 'check_ssh "$1"' _ | tee /dev/fd/3
)"

# Filter reachable IPs
IPS=($(echo "$SSH_CHECK_OUTPUT" | grep '^SSH_OK' | awk '{print $2}'))
SSH_FAIL_COUNT=$(echo "$SSH_CHECK_OUTPUT" | grep -c '^SSH_FAIL' || true)

if [[ "$SSH_FAIL_COUNT" -gt 0 ]]; then
    echo ""
    echo "[WARN] $SSH_FAIL_COUNT hosts are unreachable via SSH and will be skipped."
fi

if [[ "${#IPS[@]}" -eq 0 ]]; then
    echo "[ERROR] No hosts are reachable via SSH. Exiting." >&2
    exit 1
fi

echo ""
echo "[INFO] Mounting on ${#IPS[@]} hosts..."

# Execute mount in parallel
exec 3>&1
MOUNT_OUTPUT="$(
    printf '%s\n' "${IPS[@]}" | xargs -n 1 -P "$PARALLEL" bash -c 'run_host "$1"' _ | tee /dev/fd/3
)"

# Count results
SUCCESS_COUNT=$(echo "$MOUNT_OUTPUT" | grep -c '^OK ' || true)
FAIL_COUNT=$(echo "$MOUNT_OUTPUT" | grep -c '^FAIL ' || true)

echo ""
echo "[INFO] Mount Summary: SUCCESS=$SUCCESS_COUNT, FAIL=$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
    echo "[ERROR] Failed hosts:" >&2
    echo "$MOUNT_OUTPUT" | grep '^FAIL ' | awk '{print $2}' >&2
    exit 2
fi

echo ""
echo "[INFO] Verifying mount status on ${#IPS[@]} hosts..."

# Check mount status in parallel
exec 3>&1
MOUNT_CHECK_OUTPUT="$(
    printf '%s\n' "${IPS[@]}" | xargs -n 1 -P "$PARALLEL" bash -c 'check_mount "$1"' _ | tee /dev/fd/3
)"

MOUNT_OK_COUNT=$(echo "$MOUNT_CHECK_OUTPUT" | grep -c '^MOUNT_OK' || true)
MOUNT_FAIL_COUNT=$(echo "$MOUNT_CHECK_OUTPUT" | grep -c '^MOUNT_FAIL' || true)

echo ""
echo "[INFO] Verification Summary: OK=$MOUNT_OK_COUNT, FAIL=$MOUNT_FAIL_COUNT"

if [[ "$MOUNT_FAIL_COUNT" -ne 0 ]]; then
    echo "[ERROR] Hosts with mount failure:" >&2
    echo "$MOUNT_CHECK_OUTPUT" | grep '^MOUNT_FAIL' | awk '{print $2}' >&2
    exit 2
fi

echo "[INFO] All operations completed successfully."
exit 0
