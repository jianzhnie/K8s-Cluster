#!/usr/bin/env bash

start="${1:-bms0001}"
end="${2:-bms0448}"
label="${3}"

if [ -z "$label" ]; then
  echo "Usage: $0 <start_node> <end_node> <label>"
  echo "Example: $0 bms0001 bms0448 env=prod"
  exit 1
fi

# Strip 'bms' prefix
start_num="${start#bms}"
end_num="${end#bms}"

echo "Labeling nodes from bms${start_num} to bms${end_num} with ${label}..."

# Generate nodes list with padding (assuming 4 digits like bms0001)
nodes=$(seq -f "bms%04g" "$start_num" "$end_num")

# Apply label using xargs to handle list
echo "$nodes" | xargs kubectl label nodes --overwrite "$label"
