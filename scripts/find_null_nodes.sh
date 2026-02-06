#!/bin/bash

# 默认值
VERBOSE=true
NUM_NPUS="4"  # 空表示自动检测

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
check_npu_status() {
    local node=$1

    # 根据参数决定NPU卡数量
    local expected_npus=$NUM_NPUS

    # 使用ssh-keyscan检查目标主机指纹，防止"Host key verification failed."报错
    ssh-keyscan -H "$node" >/dev/null 2>&1

    # 尝试连接并执行命令，同时忽略ssh警告
    local output
    output=$(ssh -q -o BatchMode=yes -o ConnectTimeout=10 "$node" "npu-smi info 2>/dev/null" 2>/dev/null)

    # 如果ssh命令失败（例如连接超时），则直接判定为不可用
    if [ $? -ne 0 ]; then
        echo "🔴 节点 $node: 连接失败或命令执行失败"
        echo "$node" >> unavailable_nodes.txt
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
        echo "$node" >> unavailable_nodes.txt
        return
    fi

    if [ "$VERBOSE" = true ]; then
        echo "🔍 节点 $node: 预期NPU数量 $expected_npus, 空闲NPU数量 $empty_lines"
    fi

    # 确保所有NPU都空闲
    if [ "$empty_lines" -eq "$expected_npus" ]; then
        echo "✅ 节点 $node: 可用 ($expected_npus/$expected_npus NPU空闲)"
        echo "$node" >> available_nodes.txt
    else
        echo "❌ 节点 $node: 不可用 ($empty_lines/$expected_npus NPU空闲)"
        echo "$node" >> unavailable_nodes.txt
    fi
}

# 清理上次运行生成的临时文件
rm -f available_nodes.txt
rm -f unavailable_nodes.txt

# 统计计数器
total_nodes=${#NODE_HOSTS[@]}
available_count=0
unavailable_count=0

# 使用 GNU Parallel 来实现高效率并行执行
# 如果你的系统没有安装 parallel，可以尝试 'sudo apt-get install parallel' 或 'sudo yum install parallel'
# -j 10 指定同时运行10个任务
# --eta 显示预估剩余时间
# --bar 显示进度条
if command -v parallel &> /dev/null; then
    echo "使用 GNU Parallel 进行并行检查 (并发数: 10)..."
    export -f check_npu_status
    export NUM_NPUS
    export VERBOSE
    cat "$NODE_LIST_FILE" | parallel -j 10 --eta --bar check_npu_status
else
    echo "未找到 GNU Parallel，使用简单的 for 循环串行检查..."
    for node in "${NODE_HOSTS[@]}"; do
        check_npu_status "$node"
    done
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
