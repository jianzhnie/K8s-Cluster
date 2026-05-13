#!/bin/bash

# ==============================================================================
# 批量安装 Docker 脚本
# ==============================================================================

# 配置路径
NODE_LIST="/llm_workspace_1P/robin/node_list.txt"
DOCKER_INSTALL_SCRIPT="/llm_workspace_1P/robin/ascend-llm-ops/docker/install/batch_install_docker.sh"
DOCKER_INSTALL_DIR="/llm_workspace_1P/robin/hfhub/docker"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查本地环境（主要检查节点列表）
if [ ! -f "$NODE_LIST" ]; then
    echo -e "${RED}错误: 节点列表文件 $NODE_LIST 不存在。${NC}"
    exit 1
fi

echo -e "${YELLOW}开始批量安装 Docker (假设安装脚本已在各节点存在)...${NC}"
echo -e "节点列表: $NODE_LIST"
echo -e "安装脚本路径: $DOCKER_INSTALL_SCRIPT"
echo "----------------------------------------------------"

# 读取节点列表并执行 (使用文件描述符 9 防止 ssh 占用 stdin)
while read -u 9 -r node || [[ -n "$node" ]]; do
    # 跳过空行和注释行
    [[ -z "$node" || "$node" =~ ^# ]] && continue
    
    # 去除可能的空格
    node=$(echo "$node" | xargs)
    
    echo -e "${YELLOW}>>> 正在处理节点: $node${NC}"
    
    # 1. 检查 SSH 连通性
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -n "$node" "exit" &>/dev/null; then
        echo -e "${RED}[错误] 无法连接到节点 $node (SSH 失败)，跳过。${NC}"
        continue
    fi
    
    # 2. 执行安装逻辑
    # 直接在远程节点检查并执行安装脚本
    ssh "$node" "bash -s" <<EOF
        if ! command -v docker &> /dev/null; then
            echo "未检测到 Docker，正在执行安装脚本..."
            if [ -f "$DOCKER_INSTALL_SCRIPT" ]; then
                cd "$DOCKER_INSTALL_DIR" && sudo bash $DOCKER_INSTALL_SCRIPT
            else
                echo "错误: 远程节点未找到安装脚本 $DOCKER_INSTALL_SCRIPT"
                exit 1
            fi
        else
            echo "Docker 已安装。"
            exit 0
        fi
EOF
    
    STATUS=$?
    
    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}[完成] 节点 $node: Docker 已就绪。${NC}"
    elif [ $STATUS -eq 1 ]; then
        # 再次验证安装结果
        if ssh -n "$node" "command -v docker &> /dev/null"; then
            echo -e "${GREEN}[成功] 节点 $node: Docker 安装成功。${NC}"
        else
            echo -e "${RED}[失败] 节点 $node: Docker 安装失败或未找到脚本。${NC}"
        fi
    fi
    echo "----------------------------------------------------"
done 9< "$NODE_LIST"

echo -e "${GREEN}所有节点处理完毕。${NC}"
