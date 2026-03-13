#!/usr/bin/env bash
set -euo pipefail

LABEL_SCRIPT="${ROOT_DIR}/scripts/labeled_nodes.sh"
LABEL_KEY_VALUE="fdd-label=true"

START_NODE="bms0001"
END_NODE="bms0448"

NODES_FILE="${ROOT_DIR}/nodes.txt"

# Label nodes from bms0001 to bms0448
bash "$LABEL_SCRIPT" "$START_NODE" "$END_NODE" "$LABEL_KEY_VALUE"

# Label nodes from nodes.txt
bash "$LABEL_SCRIPT" --file "$NODES_FILE" "$LABEL_KEY_VALUE"

# Label nodes from stdin
printf "%s\n" bms1860 bms1861 bms1862 | bash "$LABEL_SCRIPT" --stdin "$LABEL_KEY_VALUE"
