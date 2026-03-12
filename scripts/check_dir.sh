#!/usr/bin/env bash

readonly SSH_OPTS=(
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

# SSH 用户配置: 优先使用环境变量，否则使用当前用户
readonly SSH_USER="${SSH_USER:-$(whoami)}"

# 统一的 SSH 执行封装
# Args:
#   $1: node (string) - 节点地址
#   $@: command (string array) - 要执行的命令
# Returns:
#   SSH 命令的退出码
ssh_run() {
    local node="$1"
    shift
    local userhost="${SSH_USER:+${SSH_USER}@}${node}"
    # 使用 $@ 确保命令中的空格和引号被正确传递
    ssh "${SSH_OPTS[@]}" "${userhost}" "$@"
}

# 日志函数 (带有 Emoji 提示)
# Args:
#   $@: msg (string) - 日志消息内容
# Returns:
#   None (输出到 stdout/stderr)
log_info() {
    local msg="$*"
    local emoji="ℹ️ "
    # 根据消息内容选择合适的emoji
    case "$msg" in
        *"开始执行"*|*"启动"*) emoji="🚀 " ;;
        *"完成"*|*"成功"*|*"通过"*) emoji="✅ " ;;
        *"失败"*|*"错误"*|*"异常"*) emoji="❌ " ;;
        *"发现"*|*"检查"*) emoji="🔍 " ;;
        *"配置"*|*"设置"*) emoji="⚙️ " ;;
        *"等待"*) emoji="⏳ " ;;
        *"清理"*) emoji="🧹 " ;;
        *"分配"*|*"部署"*) emoji="📦 " ;;
        *"节点"*|*"服务"*) emoji="💻 " ;;
        *"端口"*) emoji="🔌 " ;;
        *"文件"*) emoji="📄 " ;;
        *"统计"*) emoji="📊 " ;;
    esac
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${emoji}$msg"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: ⚠️ $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ❌ $*" >&2
}

usage() {
    cat <<EOF
使用方法:
  $0 <节点文件路径> <要检查的路径> [存在输出文件] [不存在输出文件]

示例:
  $0 nodes.txt /data/k8s exist_nodes.txt missing_nodes.txt
  SSH_USER=root $0 nodes.txt /data/k8s

可选环境变量:
  CHECK_TYPE=any|dir|file   (默认: any)
EOF
}

# 检查命令行参数，确保节点文件路径已提供
if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    usage
    exit 1
fi


NODE_LIST_FILE="$1"
CHECK_PATH="$2"
EXISTS_OUT_FILE="${3:-exist_nodes.txt}"
MISSING_OUT_FILE="${4:-missing_nodes.txt}"
CHECK_TYPE="${CHECK_TYPE:-dir}"
MAX_PARALLEL="${MAX_PARALLEL:-20}"

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

escape_single_quotes() {
    printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}
validate_node_path() {
    local node="$1"
    local path_escaped
    local test_op
    local remote_cmd

    case "$CHECK_TYPE" in
        dir) test_op="-d" ;;
        file) test_op="-f" ;;
        any) test_op="-e" ;;
        *)
            log_warn "未知 CHECK_TYPE=${CHECK_TYPE}，使用 any"
            test_op="-e"
            ;;
    esac

    path_escaped="$(escape_single_quotes "$CHECK_PATH")"
    remote_cmd="test ${test_op} '${path_escaped}'"

    ssh_run "$node" "$remote_cmd" >/dev/null 2>&1
}

: >"$EXISTS_OUT_FILE"
: >"$MISSING_OUT_FILE"

exists_count=0
missing_count=0

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/check_dir.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/exists" "$tmp_dir/missing"

sanitize_filename() {
    local s="$1"
    s="$(printf "%s" "$s" | LC_ALL=C tr -c 'A-Za-z0-9._@-' '_')"
    if [ -z "$s" ] || [ "$s" = "." ] || [ "$s" = ".." ]; then
        s="node_${RANDOM}_${RANDOM}"
    fi
    printf "%s" "$s"
}

check_one_node() {
    local node="$1"
    local out_file
    out_file="$(sanitize_filename "$node")"

    log_info "检查节点 ${node} 路径是否存在: ${CHECK_PATH}"
    if validate_node_path "$node"; then
        printf "%s\n" "$node" >"$tmp_dir/exists/$out_file"
        log_info "节点 ${node} 路径存在"
    else
        printf "%s\n" "$node" >"$tmp_dir/missing/$out_file"
        log_warn "节点 ${node} 路径不存在或 SSH 失败"
    fi
}

for node in "${NODE_HOSTS[@]}"; do
    check_one_node "$node" &
    while [ "$(jobs -p | wc -l | tr -d ' ')" -ge "$MAX_PARALLEL" ]; do
        pid="$(jobs -p | head -n 1)"
        wait "$pid"
    done
done
wait

shopt -s nullglob
exists_files=("$tmp_dir/exists/"*)
missing_files=("$tmp_dir/missing/"*)
shopt -u nullglob

if [ ${#exists_files[@]} -gt 0 ]; then
    LC_ALL=C cat "${exists_files[@]}" | sort -u >"$EXISTS_OUT_FILE"
else
    : >"$EXISTS_OUT_FILE"
fi
if [ ${#missing_files[@]} -gt 0 ]; then
    LC_ALL=C cat "${missing_files[@]}" | sort -u >"$MISSING_OUT_FILE"
else
    : >"$MISSING_OUT_FILE"
fi

exists_count="$(wc -l <"$EXISTS_OUT_FILE" | tr -d ' ')"
missing_count="$(wc -l <"$MISSING_OUT_FILE" | tr -d ' ')"

log_info "检查完成：存在 ${exists_count} 个，不存在 ${missing_count} 个"
log_info "存在节点输出：${EXISTS_OUT_FILE}"
log_info "不存在节点输出：${MISSING_OUT_FILE}"
