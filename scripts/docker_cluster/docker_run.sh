#!/bin/bash

# 引入函数库
source start_docker_image.sh

# 设置必要的环境变量
export IMAGE_NAME="cis-pengcheng.cmecloud.cn/ascendhub/mindspeed-llm"                   # 镜像名称
export IMAGE_TAG="openeuler22.03-mindspeed-llm-2.3.0-a3-arm"                            # 镜像标签
export CONTAINER_NAME="mindspeed-llm-env"                                               # 容器名称
export IMAGE_PATH="/llm_workspace_1P/robin/mindspeed-llm-2.3.0-a3-arm.tarr"      # (可选) 镜像文件路径，如果本地没有镜像会自动加载
export NPUS="0,1,2,3,4,5,6,7"                                                           # (可选) 使用的 NPU ID 列表
export SHARE_PATH_HOST="/llm_workspace_1P/robin"                                 # (可选) 挂载的共享目录
export SHARE_PATH_CONTAINER="/llm_workspace_1P/robin"                            # (可选) 挂载的共享目录

# 调用启动函数
start_docker