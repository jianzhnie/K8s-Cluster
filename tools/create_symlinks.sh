#!/bin/bash

# 检查是否提供了节点列表文件作为参数
if [ -z "$1" ]; then
    echo "用法: $0 <节点列表文件>"
    exit 1
fi

NODE_LIST="$1"

# 检查节点列表文件是否存在
if [ ! -f "$NODE_LIST" ]; then
    echo "错误: 节点列表文件 '$NODE_LIST' 不存在。"
    exit 1
fi

# 遍历每个节点并创建软链接
for node in $(cat "$NODE_LIST"); do
    echo "正在连接到节点: $node"
    ssh "root@$node" "ln -s /mnt/yWXKUIzKaqvtk0rLm/model_train/miniconda3 /home/fdd/workspace/miniconda3"
    if [ $? -eq 0 ]; then
        echo "在节点 $node 上成功创建软链接。"
    else
        echo "在节点 $node 上创建软链接失败。"
    fi
    echo "----------------------------------------"
done

echo "所有节点的软链接创建完成。"
