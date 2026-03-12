#!/usr/bin/env bash

# 默认值
VERBOSE=true
NUM_NPUS="4"  # 空表示自动检测
MAX_PARALLEL="${MAX_PARALLEL:-100}"
SSH_USER="${SSH_USER:-$(whoami)}"

SSH_OPTS=(
    -q
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
    -o ControlMaster=auto
    -o ControlPersist=60s
    -o ControlPath=/tmp/ssh_mux_%r@%h:%p
)

usage() {
    cat <<EOF
使用方法: $0 <节点文件路径>

可选环境变量:
  SSH_USER=<用户名>        (默认: 当前用户)
  NUM_NPUS=<数量>          (默认: 4)
  MAX_PARALLEL=<并发数>    (默认: 20)
  VERBOSE=true|false       (默认: true)
EOF
}

# 检查命令行参数，确保节点文件路径已提供
if [ -z "$1" ]; then
    echo "使用方法: $0 <节点文件路径>"
    echo "示例: $0 nodes.txt"
    exit 1
fi


NODE_LIST_FILE="$1"

# 检查节点文件是否存在
if [ ! -f "$NODE_LIST_FILE" ]; then
    echo "❌ 错误: 节点列表文件 '$NODE_LIST_FILE' 不存在！"
    usage
    exit 1
fi

# 从文件读取节点列表到数组 (使用 < "$VAR" 语法，并忽略空行和注释行)
mapfile -t NODE_HOSTS < <(grep -v -e '^\s*$' -e '^\s*#' "$NODE_LIST_FILE")

# 检查节点列表是否为空
if [ ${#NODE_HOSTS[@]} -eq 0 ]; then
    echo "❌ 错误: 节点列表 '$NODE_LIST_FILE' 为空。"
    exit 1
fi

echo "--- 开始检查 ${#NODE_HOSTS[@]} 个节点 ---"

# 定义一个函数，用于检查单个节点状态
sanitize_filename() {
    local s="$1"
    s="$(printf "%s" "$s" | LC_ALL=C tr -c 'A-Za-z0-9._@-' '_')"
    if [ -z "$s" ] || [ "$s" = "." ] || [ "$s" = ".." ]; then
        s="node_${RANDOM}_${RANDOM}"
    fi
    printf "%s" "$s"
}

ssh_run() {
    local node="$1"
    shift
    if [[ "$node" != *@* ]]; then
        node="${SSH_USER}@${node}"
    fi
    ssh "${SSH_OPTS[@]}" "$node" "$@"
}

check_npu_status() {
    local node="$1"

    # 根据参数决定NPU卡数量
    local expected_npus="$NUM_NPUS"

    # 尝试连接并执行命令，同时忽略ssh警告
    local output
    output="$(ssh_run "$node" "npu-smi info 2>/dev/null" 2>/dev/null)"
    local ssh_ec=$?

    # 如果ssh命令失败（例如连接超时），则直接判定为不可用
    if [ $ssh_ec -ne 0 ]; then
        echo "🔴 节点 $node: 连接失败或命令执行失败"
        printf "%s\n" "$node" >"$tmp_dir/unavailable/$(sanitize_filename "$node")"
        return
    fi

    # 检查输出中是否包含"No running processes found in NPU"
    # 我们可以通过统计"No running processes found"的行数来判断所有卡是否都空闲
    local empty_lines
    empty_lines=$(echo "$output" | grep -c "No running processes found in NPU")

    # 检查是否有错误信息
    local error_lines
    error_lines=$(echo "$output" | grep -c "Error")

    if [ "$error_lines" -gt 0 ]; then
        echo "❌ 节点 $node: NPU命令执行出错"
        printf "%s\n" "$node" >"$tmp_dir/unavailable/$(sanitize_filename "$node")"
        return
    fi

    if [ "$VERBOSE" = true ]; then
        echo "🔍 节点 $node: 预期NPU数量 $expected_npus, 空闲NPU数量 $empty_lines"
    fi

    # 确保所有NPU都空闲
    if [ "$empty_lines" -eq "$expected_npus" ]; then
        echo "✅ 节点 $node: 可用 ($expected_npus/$expected_npus NPU空闲)"
        printf "%s\n" "$node" >"$tmp_dir/available/$(sanitize_filename "$node")"
    else
        echo "❌ 节点 $node: 不可用 ($empty_lines/$expected_npus NPU空闲)"
        printf "%s\n" "$node" >"$tmp_dir/unavailable/$(sanitize_filename "$node")"
    fi
}

# 清理上次运行生成的临时文件
: >available_nodes.txt
: >unavailable_nodes.txt

# 统计计数器
total_nodes=${#NODE_HOSTS[@]}
available_count=0
unavailable_count=0

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/find_null_nodes.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/available" "$tmp_dir/unavailable"

echo "并行检查 (并发数: ${MAX_PARALLEL})..."
for node in "${NODE_HOSTS[@]}"; do
    check_npu_status "$node" &
    while [ "$(jobs -p | wc -l | tr -d ' ')" -ge "$MAX_PARALLEL" ]; do
        pid="$(jobs -p | head -n 1)"
        wait "$pid"
    done
done
wait

shopt -s nullglob
available_files=("$tmp_dir/available/"*)
unavailable_files=("$tmp_dir/unavailable/"*)
shopt -u nullglob

if [ ${#available_files[@]} -gt 0 ]; then
    LC_ALL=C cat "${available_files[@]}" | sort -u >available_nodes.txt
else
    : >available_nodes.txt
fi
if [ ${#unavailable_files[@]} -gt 0 ]; then
    LC_ALL=C cat "${unavailable_files[@]}" | sort -u >unavailable_nodes.txt
else
    : >unavailable_nodes.txt
fi

# 统计结果
if [ -f "available_nodes.txt" ]; then
    available_count=$(wc -l < available_nodes.txt)
fi

if [ -f "unavailable_nodes.txt" ]; then
    unavailable_count=$(wc -l < unavailable_nodes.txt)
fi

echo "--- 检查完成 ---"
echo "总计: $total_nodes 节点, 可用: $available_count 节点, 不可用: $unavailable_count 节点"
echo ""

echo "可用节点列表 (已保存至 available_nodes.txt):"
if [ -s "available_nodes.txt" ]; then
    cat available_nodes.txt
else
    echo "无可用节点。"
fi

echo ""
echo "不可用节点列表 (已保存至 unavailable_nodes.txt):"
if [ -s "unavailable_nodes.txt" ]; then
    cat unavailable_nodes.txt
else
    echo "无不可用节点。"
fi
