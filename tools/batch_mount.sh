#!/bin/bash
# ============================================================
# 集群节点批量挂载脚本
# 通过 SSH 在远程节点批量执行 dtfs 挂载
#
# 用法：
#   ./batch_mount.sh -f <节点列表文件> [-u 用户名] [-p 密码]
#                    [-s 挂载源] [-d 挂载点] [-t 文件系统类型]
#
# 示例：
#   ./batch_mount.sh -f nodes.txt -u root -p 'mypassword'
#   ./batch_mount.sh -f nodes.txt -u root -s /llmtuner -d /home/jianzhnie/llmtuner
#   ./batch_mount.sh -f nodes.txt -u root -p 'pass' -t nfs -s 10.0.0.1:/data -d /mnt/data
#
# 节点列表文件格式（每行一个IP/主机名，支持 # 注释和空行）：
#   10.1.0.17
#   10.1.0.18
# ============================================================

set -uo pipefail

SSH_USER=""
SSH_PASSWORD=""
NODE_FILE=""
MOUNT_SRC="/llmtuner"
MOUNT_DST="/home/jianzhnie/llmtuner"
MOUNT_TYPE="dtfs"
PARALLEL=8
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"

usage() {
    cat <<EOF
用法: $(basename "$0") -f <节点列表文件> [选项]

选项:
  -f FILE    节点列表文件（每行一个IP，支持#注释和空行）
  -u USER    SSH 用户名（默认: root）
  -p PASS    SSH 密码（未指定则使用密钥或交互式输入）
  -s SRC     挂载源（默认: /llmtuner）
  -d DST     挂载目标路径（默认: /home/jianzhnie/llmtuner）
  -t TYPE    文件系统类型（默认: dtfs）
  -n NUM     并行度（默认: 8）
  -h         显示帮助信息

示例:
  $(basename "$0") -f nodes.txt -u root -p 'iX5@vSogl9'
  $(basename "$0") -f nodes.txt -u root -s /llmtuner -d /home/jianzhnie/llmtuner
  $(basename "$0") -f nodes.txt -u root -t nfs -s 10.0.0.1:/share -d /mnt/share
EOF
    exit "${1:-0}"
}

while getopts "f:u:p:s:d:t:n:h" opt; do
    case "$opt" in
        f) NODE_FILE="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        p) SSH_PASSWORD="$OPTARG" ;;
        s) MOUNT_SRC="$OPTARG" ;;
        d) MOUNT_DST="$OPTARG" ;;
        t) MOUNT_TYPE="$OPTARG" ;;
        n) PARALLEL="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

if [[ -z "$NODE_FILE" ]]; then
    echo "错误: 必须通过 -f 指定节点列表文件"
    usage 1
fi

if [[ ! -f "$NODE_FILE" ]]; then
    echo "错误: 节点列表文件不存在: $NODE_FILE"
    exit 1
fi

[[ -z "$SSH_USER" ]] && SSH_USER="root"

if [[ -z "$SSH_PASSWORD" ]]; then
    read -rsp "请输入 ${SSH_USER} 的 SSH 密码（直接回车则使用密钥认证）: " SSH_PASSWORD
    echo
fi

NODES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -n "$line" ]] && NODES+=("$line")
done < "$NODE_FILE"

if [[ ${#NODES[@]} -eq 0 ]]; then
    echo "错误: 节点列表为空"
    exit 1
fi

echo "============================================"
echo " 集群批量挂载"
echo " 用户: $SSH_USER"
echo " 节点数: ${#NODES[@]}"
echo " 挂载: mount -t $MOUNT_TYPE $MOUNT_SRC $MOUNT_DST"
echo "============================================"
echo ""

ssh_cmd() {
    local node="$1"
    shift
    if [[ -n "$SSH_PASSWORD" ]]; then
        sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS ${SSH_USER}@${node} "$@"
    else
        ssh $SSH_OPTS ${SSH_USER}@${node} "$@"
    fi
}

if [[ -n "$SSH_PASSWORD" ]] && ! command -v sshpass &>/dev/null; then
    echo "错误: 需要 sshpass 工具，请先安装 (apt install sshpass / yum install sshpass)"
    exit 1
fi

echo "=== Step 1/2: 执行挂载 ==="
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_NODES=()

for node in "${NODES[@]}"; do
    printf "  [%02d/%02d] %-20s " "$((SUCCESS_COUNT + FAIL_COUNT + SKIP_COUNT + 1))" "${#NODES[@]}" "$node"

    RESULT=$(ssh_cmd "$node" bash -s <<REMOTE_EOF 2>&1
mkdir -p "$MOUNT_DST"

if mount | grep -q " $MOUNT_DST "; then
    echo "ALREADY_MOUNTED"
    exit 0
fi

mount -t "$MOUNT_TYPE" "$MOUNT_SRC" "$MOUNT_DST"
if mount | grep -q " $MOUNT_DST "; then
    echo "MOUNT_OK"
else
    echo "MOUNT_FAIL"
    exit 1
fi
REMOTE_EOF
    )
    EXIT_CODE=$?

    if echo "$RESULT" | grep -q "ALREADY_MOUNTED"; then
        echo "已挂载(跳过)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    elif [[ $EXIT_CODE -eq 0 ]] && echo "$RESULT" | grep -q "MOUNT_OK"; then
        echo "OK"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "FAILED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NODES+=("$node")
    fi
done

echo ""
echo "  新挂载: ${SUCCESS_COUNT}  已挂载: ${SKIP_COUNT}  失败: ${FAIL_COUNT}"
if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo "  失败节点: ${FAILED_NODES[*]}"
fi
echo ""

echo "=== Step 2/2: 验证挂载状态 ==="
VERIFY_FAIL=0
for node in "${NODES[@]}"; do
    printf "  %-20s " "$node"
    DF_OUT=$(ssh_cmd "$node" "df -h '$MOUNT_DST' 2>/dev/null | tail -1" 2>/dev/null)
    if [[ -n "$DF_OUT" ]] && echo "$DF_OUT" | grep -q "$MOUNT_DST"; then
        SIZE=$(echo "$DF_OUT" | awk '{print $2}')
        USED=$(echo "$DF_OUT" | awk '{print $5}')
        echo "OK (${SIZE}, 使用${USED})"
    else
        echo "未挂载"
        VERIFY_FAIL=$((VERIFY_FAIL + 1))
    fi
done

echo ""
echo "============================================"
if [[ $VERIFY_FAIL -eq 0 ]]; then
    echo " 完成！所有 ${#NODES[@]} 个节点挂载正常"
else
    echo " 完成！${VERIFY_FAIL} 个节点挂载异常，请检查"
fi
echo "============================================"
