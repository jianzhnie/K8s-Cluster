#!/usr/bin/env bash

mode="${1:-}"

if [ "$mode" = "-f" ] || [ "$mode" = "--file" ]; then
  nodes_file="${2:-}"
  label="${3:-}"
  if [ -z "$nodes_file" ] || [ -z "$label" ]; then
    echo "Usage: $0 --file <nodes_file> <label>"
    echo "Example: $0 --file nodes.txt env=prod"
    exit 1
  fi

  if [ ! -f "$nodes_file" ]; then
    echo "Nodes file not found: $nodes_file"
    exit 1
  fi

  nodes_count="$(awk 'NF && $1 !~ /^#/' "$nodes_file" | tr -d '\r' | wc -l | tr -d ' ')"
  if [ "$nodes_count" -eq 0 ]; then
    echo "No nodes found in file: $nodes_file"
    exit 1
  fi

  echo "Labeling ${nodes_count} nodes from file ${nodes_file} with ${label}..."
  awk 'NF && $1 !~ /^#/' "$nodes_file" | tr -d '\r' | LABEL="$label" xargs -n 50 sh -c 'kubectl label nodes "$@" --overwrite "$LABEL"' _
  exit 0
fi

if [ "$mode" = "-" ] || [ "$mode" = "--stdin" ]; then
  label="${2:-}"
  if [ -z "$label" ]; then
    echo "Usage: $0 --stdin <label>"
    echo "Example: cat nodes.txt | $0 --stdin env=prod"
    exit 1
  fi

  echo "Labeling nodes from stdin with ${label}..."
  awk 'NF && $1 !~ /^#/' | tr -d '\r' | LABEL="$label" xargs -n 50 sh -c 'kubectl label nodes "$@" --overwrite "$LABEL"' _
  exit 0
fi

start="${1:-bms0001}"
end="${2:-bms0448}"
label="${3:-}"

if [ -z "$label" ]; then
  echo "Usage: $0 <start_node> <end_node> <label>"
  echo "Example: $0 bms0001 bms0448 env=prod"
  echo "       $0 --file nodes.txt env=prod"
  echo "       cat nodes.txt | $0 --stdin env=prod"
  exit 1
fi

# Strip 'bms' prefix
start_num="${start#bms}"
end_num="${end#bms}"

echo "Labeling nodes from bms${start_num} to bms${end_num} with ${label}..."

# Apply label using xargs to handle list
seq -f "bms%04g" "$start_num" "$end_num" | LABEL="$label" xargs -n 50 sh -c 'kubectl label nodes "$@" --overwrite "$LABEL"' _
