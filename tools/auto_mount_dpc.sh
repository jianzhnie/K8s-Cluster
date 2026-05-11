#!/bin/bash

usage() {
    cat <<EOF
Usage: $0 -file <node_list_file> -source <source> -target <target> [-mount <mount_type>] [-user <user>]

Options:
  -file    Node list file (required)
  -source  Source path to mount (required)
  -target  Target mount point (required)
  -mount   Mount type (default: dtfs)
  -user    SSH user (default: root)

Example:
  $0 -file nodes.txt -source /llmtuner -target /home/jianzhnie/llmtuner
  $0 -file nodes.txt -source /llmtuner -target /home/jianzhnie/llmtuner -mount dpc
  $0 -file nodes.txt -source /llmtuner -target /home/jianzhnie/llmtuner -mount dtfs -user root
EOF
    exit 1
}

SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
MOUNT_TYPE="dtfs"
user="root"

while [ $# -gt 0 ]; do
    case "$1" in
        -file)   NODE_LIST_FILE="$2"; shift 2 ;;
        -source) SOURCE="$2"; shift 2 ;;
        -target) TARGET="$2"; shift 2 ;;
        -mount)  MOUNT_TYPE="$2"; shift 2 ;;
        -user)   user="$2"; shift 2 ;;
        -h|-help) usage ;;
        *) echo "Error: Unknown option $1" >&2; usage ;;
    esac
done

[ -z "$NODE_LIST_FILE" ] || [ -z "$SOURCE" ] || [ -z "$TARGET" ] && usage

if [ ! -f "$NODE_LIST_FILE" ]; then
    echo "Error: Node list file '$NODE_LIST_FILE' not found!" >&2
    exit 1
fi

mapfile -t NODE_HOSTS < <(grep -v -e '^\s*$' -e '^\s*#' "$NODE_LIST_FILE")

if [ ${#NODE_HOSTS[@]} -eq 0 ]; then
    echo "Error: Node list '$NODE_LIST_FILE' is empty." >&2
    exit 1
fi

mount_on_node() {
    local node="$1"
    echo "Processing node: $node"

    ssh $SSH_OPTS "${user}@${node}" "
        TARGET='$TARGET'; SOURCE='$SOURCE'; MT='$MOUNT_TYPE'

        if mountpoint -q \"\$TARGET\"; then
            echo \"  \$TARGET is already mounted\"
            exit 0
        fi

        if [ ! -d \"\$TARGET\" ]; then
            sudo mkdir -p \"\$TARGET\"
        fi

        if ! sudo mount -t \"\$MT\" \"\$SOURCE\" \"\$TARGET\"; then
            echo \"  Failed to mount on $node (type: \$MT)\" >&2
            exit 1
        fi

        if mountpoint -q \"\$TARGET\"; then
            echo \"  Mounted \$SOURCE -> \$TARGET (type: \$MT)\"
        else
            echo \"  Failed to mount on $node (type: \$MT)\" >&2
            exit 1
        fi
    "
}

fail=0
for node in "${NODE_HOSTS[@]}"; do
    mount_on_node "$node" &
done

for pid in $(jobs -p); do
    if ! wait "$pid"; then
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "All mount operations completed successfully."
else
    echo "Some mount operations failed." >&2
    exit 1
fi
