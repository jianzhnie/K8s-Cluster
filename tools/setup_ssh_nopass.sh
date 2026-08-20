#!/bin/bash
# ============================================================
# 集群节点免密登录配置脚本
# 策略：生成统一密钥对，分发到所有节点，实现任意两节点互通
#
# 用法：
#   ./setup_ssh_nopass.sh -f <节点列表文件> [-u 用户名] [-p 密码] [-c]
#
# 示例：
#   ./setup_ssh_nopass.sh -f nodes.txt -u root -p 'mypassword'
#   ./setup_ssh_nopass.sh -f nodes.txt -u root   # 交互式输入密码
#   ./setup_ssh_nopass.sh -f nodes.txt -u root -c # 仅检查免密状态
#
# 节点列表文件格式（每行一个IP/主机名，支持 # 注释和空行）：
#   10.1.0.17
#   10.1.0.18
#   # 这是注释
#   10.1.0.19
# ============================================================

set -euo pipefail

SSH_USER=""
SSH_PASSWORD=""
NODE_FILE=""
CHECK_ONLY=false
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"

usage() {
    cat <<EOF
用法: $(basename "$0") -f <节点列表文件> [-u 用户名] [-p 密码] [-c]

选项:
  -f FILE    节点列表文件（每行一个IP，支持#注释和空行）
  -u USER    SSH 用户名（默认: root）
  -p PASS    SSH 密码（未指定则交互式输入）
  -c          仅检查免密状态，不执行分发
  -h         显示帮助信息

示例:
  $(basename "$0") -f nodes.txt -u root -p 'iX5@vSogl9'
  $(basename "$0") -f nodes.txt -u root -c   # 仅检查
EOF
    exit "${1:-0}"
}

while getopts "f:u:p:ch" opt; do
    case "$opt" in
        f) NODE_FILE="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        p) SSH_PASSWORD="$OPTARG" ;;
        c) CHECK_ONLY=true ;;
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

NODES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -n "$line" ]] && NODES+=("$line")
done < "$NODE_FILE"

if [[ ${#NODES[@]} -lt 1 ]]; then
    echo "错误: 节点列表为空"
    exit 1
fi

if [[ "$CHECK_ONLY" != true ]]; then
    if [[ ${#NODES[@]} -lt 2 ]]; then
        echo "错误: 免密分发需要至少 2 个节点，当前: ${#NODES[@]}"
        exit 1
    fi

    if [[ -z "$SSH_PASSWORD" ]]; then
        read -rsp "请输入 ${SSH_USER} 的 SSH 密码: " SSH_PASSWORD
        echo
    fi

    if ! command -v sshpass &>/dev/null; then
        echo "错误: 需要 sshpass 工具，请先安装 (apt install sshpass / yum install sshpass)"
        exit 1
    fi
fi

echo "============================================"
if [[ "$CHECK_ONLY" == true ]]; then
    echo " 集群免密登录检查"
else
    echo " 集群免密登录配置"
fi
echo " 用户: $SSH_USER"
echo " 节点数: ${#NODES[@]}"
echo " 节点列表: ${NODE_FILE}"
echo "============================================"
echo ""

if [[ "$CHECK_ONLY" == true ]]; then
    # ── 仅检查模式 ────────────────────────────────────────
    echo "=== 检查各节点免密状态 ==="
    ALL_OK=true
    FAILED_CHECK=()
    i=0

    for node in "${NODES[@]}"; do
        i=$((i + 1))
        printf "  [%02d/%02d] %-20s " "$i" "${#NODES[@]}" "$node"
        if [[ -n "$SSH_PASSWORD" ]]; then
            if sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS ${SSH_USER}@${node} "echo ok" 2>/dev/null | grep -q "ok"; then
                echo "免密已配置"
            else
                echo "免密未配置"
                ALL_OK=false
                FAILED_CHECK+=("$node")
            fi
        else
            if ssh $SSH_OPTS ${SSH_USER}@${node} "echo ok" 2>/dev/null | grep -q "ok"; then
                echo "免密已配置"
            else
                echo "免密未配置"
                ALL_OK=false
                FAILED_CHECK+=("$node")
            fi
        fi
    done

    echo ""
    echo "============================================"
    if [[ "$ALL_OK" == true ]]; then
        echo " ✓ 所有 ${#NODES[@]} 个节点免密已就绪"
    else
        echo " ✗ ${#FAILED_CHECK[@]}/${#NODES[@]} 个节点免密未配置:"
        printf "   %s\n" "${FAILED_CHECK[@]}"
        echo ""
        echo " 请运行: $(basename "$0") -f $NODE_FILE -u $SSH_USER -p '<密码>'"
        exit 1
    fi
    echo "============================================"
    exit 0
fi

# ── 配置模式 ──────────────────────────────────────────────

WORK_DIR=$(mktemp -d)
KEYFILE="$WORK_DIR/id_rsa"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "=== Step 1/3: 生成共享密钥对 ==="
ssh-keygen -t rsa -b 4096 -f "$KEYFILE" -N "" -q
PUBKEY=$(cat "$KEYFILE.pub")
PRIVKEY=$(cat "$KEYFILE")
echo "  密钥对已生成 (RSA 4096-bit)"
echo ""

echo "=== Step 2/3: 分发密钥到所有节点 ==="
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_NODES=()

for node in "${NODES[@]}"; do
    printf "  [%02d/%02d] %-20s " "$((SUCCESS_COUNT + FAIL_COUNT + 1))" "${#NODES[@]}" "$node"

    if sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS ${SSH_USER}@${node} bash -s <<REMOTE_EOF
set -e
mkdir -p ~/.ssh && chmod 700 ~/.ssh

cat > ~/.ssh/id_rsa << 'KEYEOF'
${PRIVKEY}
KEYEOF
chmod 600 ~/.ssh/id_rsa

cat > ~/.ssh/id_rsa.pub << 'KEYEOF'
${PUBKEY}
KEYEOF
chmod 644 ~/.ssh/id_rsa.pub

grep -qF "${PUBKEY}" ~/.ssh/authorized_keys 2>/dev/null || echo "${PUBKEY}" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

if ! grep -q "StrictHostKeyChecking no" ~/.ssh/config 2>/dev/null; then
    cat >> ~/.ssh/config << 'CONFEOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
CONFEOF
    chmod 600 ~/.ssh/config
fi
REMOTE_EOF
    then
        echo "OK"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "FAILED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NODES+=("$node")
    fi
done

echo ""
echo "  成功: ${SUCCESS_COUNT}  失败: ${FAIL_COUNT}"
if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo "  失败节点: ${FAILED_NODES[*]}"
    echo ""
    echo "  可能原因:"
    echo "    1. 节点 IP 不可达（检查网络/防火墙）"
    echo "    2. SSH 端口不正确"
    echo "    3. 用户名/密码错误"
    echo "    4. 节点 SSH 服务未启动"
fi
echo ""

echo "=== Step 3/3: 验证免密登录 ==="
VERIFY_SRC="${NODES[0]}"
VERIFY_DST="${NODES[1]}"
printf "  测试 %s -> %s: " "$VERIFY_SRC" "$VERIFY_DST"

RESULT=$(sshpass -p "$SSH_PASSWORD" ssh $SSH_OPTS ${SSH_USER}@${VERIFY_SRC} \
    "ssh ${SSH_USER}@${VERIFY_DST} hostname" 2>/dev/null)

if [[ $? -eq 0 && -n "$RESULT" ]]; then
    echo "$RESULT"
    echo "  ✓ 免密登录验证成功"
else
    echo ""
    echo "  ✗ 验证失败，请检查网络或配置"
fi

echo ""
echo "============================================"
echo " 配置完成！${SUCCESS_COUNT} 个节点已实现免密互通"
echo "============================================"
