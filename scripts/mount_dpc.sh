#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IP_LIST_FILE="${1:-$SCRIPT_DIR/df_ip_list.txt}"

PARALLEL="${PARALLEL:-16}"
RETRIES="${RETRIES:-3}"

REMOTE_MOUNTPOINT="${REMOTE_MOUNTPOINT:-/llm_workspace_1P}"
REMOTE_UMOUNT_PATHS="${REMOTE_UMOUNT_PATHS:-/mnt/9w1N7vBPmO3wMAYjqZL /mnt/yWXKUIzKaqvtk0rLm /mnt/model_test /mnt/bigio /mnt/mpi_tools /mnt/case_test /mnt/c3_test}"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

if [[ ! -f "$IP_LIST_FILE" ]]; then
  echo "[ERROR] ip list not found: $IP_LIST_FILE" >&2
  exit 1
fi

REMOTE_CMD=$(
  cat <<'EOF'
set -euo pipefail
for p in __UMOUNT_PATHS__; do
  umount -f "$p" >/dev/null 2>&1 || true
done
mkdir -p "__MOUNTPOINT__"
if command -v mountpoint >/dev/null 2>&1; then
  mountpoint -q "__MOUNTPOINT__" || mount -t dtfs "__MOUNTPOINT__" "__MOUNTPOINT__"
else
  mount | grep -q " on __MOUNTPOINT__ " || mount -t dtfs "__MOUNTPOINT__" "__MOUNTPOINT__"
fi
EOF
)
REMOTE_CMD="${REMOTE_CMD/__UMOUNT_PATHS__/$REMOTE_UMOUNT_PATHS}"
REMOTE_CMD="${REMOTE_CMD/__MOUNTPOINT__/$REMOTE_MOUNTPOINT}"

RESULTS_FILE="$(mktemp -t mount_dpc_results.XXXXXX)"
cleanup() { rm -f "$RESULTS_FILE"; }
trap cleanup EXIT

export REMOTE_CMD RETRIES RESULTS_FILE REMOTE_MOUNTPOINT

run_one() {
  local ip="$1"
  local attempt=1
  while [[ "$attempt" -le "$RETRIES" ]]; do
    if ssh "${SSH_OPTS[@]}" "$ip" "$REMOTE_CMD" >/dev/null 2>&1; then
      echo "OK $ip" >>"$RESULTS_FILE"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$attempt"
  done
  echo "FAIL $ip" >>"$RESULTS_FILE"
  return 1
}
export -f run_one

mapfile -t IPS < <(grep -Ehv '^\s*($|#)' "$IP_LIST_FILE" | awk '{print $1}' | sort -u)
if [[ "${#IPS[@]}" -eq 0 ]]; then
  echo "[ERROR] empty ip list: $IP_LIST_FILE" >&2
  exit 1
fi

printf '%s\n' "${IPS[@]}" | xargs -n 1 -P "$PARALLEL" bash -c 'run_one "$1"' _

total="$(wc -l <"$RESULTS_FILE" | tr -d ' ')"
ok="$(grep -c '^OK ' "$RESULTS_FILE" || true)"
fail="$(grep -c '^FAIL ' "$RESULTS_FILE" || true)"

echo "[INFO] total=$total ok=$ok fail=$fail mountpoint=$REMOTE_MOUNTPOINT"
if [[ "$fail" -ne 0 ]]; then
  echo "[ERROR] failed hosts:" >&2
  grep '^FAIL ' "$RESULTS_FILE" | awk '{print $2}' >&2
  exit 2
fi
