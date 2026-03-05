#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IP_LIST_FILE="${1:-$SCRIPT_DIR/df_ip_list.txt}"

PARALLEL="${PARALLEL:-16}"
RETRIES="${RETRIES:-1}"

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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $(basename "$0") [ip_list_file]"
  echo "Env: PARALLEL RETRIES REMOTE_MOUNTPOINT REMOTE_UMOUNT_PATHS"
  exit 0
fi

if [[ ! -f "$IP_LIST_FILE" ]]; then
  echo "[ERROR] ip list not found: $IP_LIST_FILE" >&2
  exit 1
fi

do_umount() {
  local ip="$1"
  if [[ -n "${REMOTE_UMOUNT_PATHS// }" ]]; then
    local cmd="for p in $REMOTE_UMOUNT_PATHS; do umount -f \"\$p\" >/dev/null 2>&1 || true; done"
    ssh "${SSH_OPTS[@]}" "$ip" "$cmd" >/dev/null 2>&1 || true
  fi
}

do_mount() {
  local ip="$1"
  local cmd="mkdir -p \"$REMOTE_MOUNTPOINT\"; "
  cmd+="mount -t dtfs \"$REMOTE_MOUNTPOINT\" \"$REMOTE_MOUNTPOINT\""
  ssh "${SSH_OPTS[@]}" "$ip" "$cmd" >/dev/null 2>&1
}

export -f do_umount do_mount

run_one() {
  local ip="$1"
  local attempt=1
  while [[ "$attempt" -le "$RETRIES" ]]; do
    if do_umount "$ip" && do_mount "$ip"; then
      echo "OK $ip"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$attempt"
  done
  echo "FAIL $ip"
  return 1
}
export -f run_one

mapfile -t IPS < <(grep -Ehv '^\s*($|#)' "$IP_LIST_FILE" | awk '{print $1}' | sort -u)
if [[ "${#IPS[@]}" -eq 0 ]]; then
  echo "[ERROR] empty ip list: $IP_LIST_FILE" >&2
  exit 1
fi

exec 3>&1
OUTPUT="$(
  printf '%s\n' "${IPS[@]}" | xargs -n 1 -P "$PARALLEL" bash -c 'run_one "$1"' _ | tee >(cat >&3)
)"
total="$(printf '%s\n' "$OUTPUT" | grep -E '^(OK|FAIL) ' | wc -l | tr -d ' ')"
ok="$(printf '%s\n' "$OUTPUT" | grep -c '^OK ' || true)"
fail="$(printf '%s\n' "$OUTPUT" | grep -c '^FAIL ' || true)"
echo "[INFO] total=$total ok=$ok fail=$fail mountpoint=$REMOTE_MOUNTPOINT"
if [[ "$fail" -ne 0 ]]; then
  echo "[ERROR] failed hosts:" >&2
  printf '%s\n' "$OUTPUT" | awk '/^FAIL /{print $2}' >&2
  exit 2
fi
