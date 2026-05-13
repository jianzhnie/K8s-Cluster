#!/bin/bash
# Parallel Docker CE installer across multiple nodes
# Usage: bash install_docker_cluster.sh [NODES_FILE]
#   NODES_FILE: one IP or hostname per line (default: nodes.txt)
#
# The install script (instll_docker_ce.sh) is copied to each remote node
# and executed there. The ISO must already exist on each node at the path
# specified by DOCKER_ISO_PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/instll_docker_ce.sh"
NODES_FILE="${1:-${SCRIPT_DIR}/nodes.txt}"
SSH_USER="${SSH_USER:-root}"
SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
PARALLEL_LOG_DIR="/tmp/docker_install_logs_$(date +%Y%m%d_%H%M%S)"

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "===================================================="
echo "  PARALLEL DOCKER CE CLUSTER INSTALLER - $TIMESTAMP"
echo "===================================================="
echo "[ENV] Install Script: $INSTALL_SCRIPT"
echo "[ENV] Nodes File:     $NODES_FILE"
echo "[ENV] SSH User:       $SSH_USER"
echo "[ENV] Log Dir:        $PARALLEL_LOG_DIR"
echo "===================================================="

# Pre-flight checks
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "[ERROR] Install script not found: $INSTALL_SCRIPT"
    exit 1
fi

if [[ ! -f "$NODES_FILE" ]]; then
    echo "[ERROR] Nodes file not found: $NODES_FILE"
    echo "[INFO]  Create a file with one IP/hostname per line, e.g.:"
    echo "        10.42.15.194"
    echo "        10.42.15.195"
    exit 1
fi

# Read nodes (skip empty lines and comments)
NODES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/#.*//' | xargs)
    [[ -z "$line" ]] && continue
    NODES+=("$line")
done < "$NODES_FILE"

if [[ ${#NODES[@]} -eq 0 ]]; then
    echo "[ERROR] No valid nodes found in $NODES_FILE"
    exit 1
fi

echo "[INFO] Found ${#NODES[@]} node(s): ${NODES[*]}"
echo ""

mkdir -p "$PARALLEL_LOG_DIR"

# Detect local IPs to skip SSH for localhost
LOCAL_IPS=$(hostname -I 2>/dev/null || echo "")
is_local() {
    local ip=$1
    for lip in $LOCAL_IPS; do
        [[ "$ip" == "$lip" ]] && return 0
    done
    [[ "$ip" == "localhost" || "$ip" == "127.0.0.1" || "$ip" == "$(hostname)" ]] && return 0
    return 1
}

# Check if Docker is already installed on a node
docker_already_installed() {
    local host=$1
    if is_local "$host"; then
        docker --version &>/dev/null && return 0
    else
        ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
            "${SSH_USER}@${host}" "docker --version" &>/dev/null && return 0
    fi
    return 1
}

# Install Docker on a single node
install_on_node() {
    local host=$1
    local log_file="${PARALLEL_LOG_DIR}/${host}.log"

    {
        echo "[$(date '+%H:%M:%S')] === Checking Docker on ${host} ==="

        if docker_already_installed "$host"; then
            local ver
            if is_local "$host"; then
                ver=$(docker --version 2>/dev/null)
            else
                ver=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
                    "${SSH_USER}@${host}" "docker --version" 2>/dev/null)
            fi
            echo "[$(date '+%H:%M:%S')] Docker already installed: $ver"
            echo "SKIPPED"
            return 0
        fi

        echo "[$(date '+%H:%M:%S')] Docker not found, starting installation..."

        if is_local "$host"; then
            echo "[$(date '+%H:%M:%S')] Local node detected, running directly..."
            bash "$INSTALL_SCRIPT"
        else
            # Test SSH connectivity
            if ! ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
                    "${SSH_USER}@${host}" "echo ok" &>/dev/null; then
                echo "[$(date '+%H:%M:%S')] ERROR: SSH connection failed (check SSH key & user)"
                echo "FAIL:SSH_CONNECTION"
                return 1
            fi

            # Copy install script to remote node
            echo "[$(date '+%H:%M:%S')] Copying install script to ${host}..."
            scp -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
                "$INSTALL_SCRIPT" "${SSH_USER}@${host}:/tmp/instll_docker_ce.sh"

            # Execute install script on remote node
            echo "[$(date '+%H:%M:%S')] Running install script on ${host}..."
            ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
                "${SSH_USER}@${host}" "bash /tmp/instll_docker_ce.sh"

            # Cleanup
            ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
                "${SSH_USER}@${host}" "rm -f /tmp/instll_docker_ce.sh" 2>/dev/null || true
        fi

        echo "[$(date '+%H:%M:%S')] === Completed Docker install on ${host} ==="
        echo "SUCCESS"

    } &> "$log_file"

    return $?
}

# ---------------------------------------------------------------------------
# Launch parallel installs
# ---------------------------------------------------------------------------
echo "[$TIMESTAMP] [INFO] Launching parallel install on ${#NODES[@]} node(s)..."
echo ""

PIDS=()
for host in "${NODES[@]}"; do
    install_on_node "$host" &
    PIDS+=($!)
    echo "  -> Started on ${host} (PID: ${!})"
done

echo ""
echo "[INFO] Waiting for all nodes to complete..."
echo ""

# Wait for all background jobs and collect results
FAILED_HOSTS=()
SUCCESS_HOSTS=()
SKIPPED_HOSTS=()

for i in "${!NODES[@]}"; do
    host="${NODES[$i]}"
    pid="${PIDS[$i]}"

    if wait "$pid" 2>/dev/null; then
        log_file="${PARALLEL_LOG_DIR}/${host}.log"
        if grep -q "^SKIPPED$" "$log_file" 2>/dev/null; then
            SKIPPED_HOSTS+=("$host")
            echo "  [SKIP]  ${host}  (already installed)"
        else
            SUCCESS_HOSTS+=("$host")
            echo "  [OK]    ${host}"
        fi
    else
        FAILED_HOSTS+=("$host")
        echo "  [FAIL]  ${host}  -> see ${PARALLEL_LOG_DIR}/${host}.log"
    fi
done

echo ""
echo "===================================================="
echo "  INSTALLATION SUMMARY"
echo "===================================================="
echo "Total:   ${#NODES[@]}"
echo "Success: ${#SUCCESS_HOSTS[@]} (fresh install)"
echo "Skipped: ${#SKIPPED_HOSTS[@]} (already installed)"
echo "Failed:  ${#FAILED_HOSTS[@]}"
[[ ${#SUCCESS_HOSTS[@]} -gt 0 ]] && echo "  OK:     ${SUCCESS_HOSTS[*]}"
[[ ${#SKIPPED_HOSTS[@]} -gt 0 ]]  && echo "  SKIP:   ${SKIPPED_HOSTS[*]}"
[[ ${#FAILED_HOSTS[@]} -gt 0 ]]   && echo "  FAIL:   ${FAILED_HOSTS[*]}"
echo "Logs: $PARALLEL_LOG_DIR"
echo "===================================================="

[[ ${#FAILED_HOSTS[@]} -gt 0 ]] && exit 1
exit 0
