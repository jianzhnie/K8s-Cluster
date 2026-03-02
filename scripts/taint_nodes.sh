#!/usr/bin/env bash

set -euo pipefail

start="${1:-bms0385}"
end="${2:-bms0447}"
taint="${3:-node-status=bad:NoExecute}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 <start_node> <end_node> [taint]"
  echo "Example: $0 bms0385 bms0447 node-status=bad:NoExecute"
  echo "Example(remove): $0 bms0385 bms0447 node-status-"
  exit 0
fi

start_num="${start#bms}"
end_num="${end#bms}"

if [[ -z "$start_num" || -z "$end_num" || ! "$start_num" =~ ^[0-9]+$ || ! "$end_num" =~ ^[0-9]+$ ]]; then
  echo "Invalid node range: start='$start' end='$end'" >&2
  echo "Expected formats like: bms0385 bms0447 (or 0385 0447)" >&2
  exit 1
fi

width=4
if (( ${#start_num} > width )); then width=${#start_num}; fi
if (( ${#end_num} > width )); then width=${#end_num}; fi

echo "Tainting nodes from bms$(printf "%0${width}d" "$start_num") to bms$(printf "%0${width}d" "$end_num") with ${taint}..."

fmt="bms%0${width}g"
nodes="$(seq -f "$fmt" "$start_num" "$end_num")"
echo "$nodes" | xargs kubectl taint nodes --overwrite "$taint"
