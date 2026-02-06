#!/bin/bash

# =============================================================================
# K8s Cluster Common Environment Setup Script
# 用于初始化 Ascend/HCCL 训练环境，连接 K8s 注入的环境变量
# =============================================================================

# source /usr/local/Ascend/ascend-toolkit/set_env.sh
source ~/.bashrc

# -----------------------------------------------------------------------------
# 1. 目录创建与日志路径配置
# -----------------------------------------------------------------------------
# 检查 MINDX_TASK_ID (由 ascend-operator 注入)
if [ -z "$MINDX_TASK_ID" ]; then
    echo "Warning: MINDX_TASK_ID is not set. Using 'default_task' for log paths."
    MINDX_TASK_ID="default_task"
fi

# 检查 XDL_IP 和 RANK
XDL_IP=${XDL_IP:-"127.0.0.1"}
RANK=${RANK:-0}

mkdir -p /job/code/alllogs/$MINDX_TASK_ID/ttplogs
mkdir -p /job/code/alllogs/$MINDX_TASK_ID/trainlogs
mkdir -p /job/data/output/ckpt

# 环境变量用于断点续训
export RESUME_MODE_ENABLE=1

# 日志级别与路径
export ASCEND_GLOBAL_LOG_LEVEL=2  # info level
export ASCEND_PROCESS_LOG_PATH=/job/code/alllogs/$MINDX_TASK_ID/plogs/$XDL_IP
export TTP_LOG_PATH=/job/code/alllogs/$MINDX_TASK_ID/ttplogs/ttplog$XDL_IP-$RANK
export TRAIN_LOG_PATH=/job/code/alllogs/$MINDX_TASK_ID/trainlogs/$XDL_IP-$RANK

# -----------------------------------------------------------------------------
# 2. Ascend & HCCL 基础配置
# -----------------------------------------------------------------------------
export HCCL_ASYNC_ERROR_HANDLING=0  # 0: 关闭 watchdog，避免影响进程级恢复
export HCCL_WHITELIST_DISABLE=1

# 网卡配置 (默认 enp66s0f0，可被外部环境变量覆盖)
export GLOO_SOCKET_IFNAME=${GLOO_SOCKET_IFNAME:-enp66s0f0}
export HCCL_SOCKET_IFNAME=${HCCL_SOCKET_IFNAME:-enp66s0f0}

export TTP_OT=360
export HCCL_CONNECT_TIMEOUT=1800
export CUDA_DEVICE_MAX_CONNECTIONS=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export NPU_ASD_ENABLE=0
export TASK_QUEUE_ENABLE=2

# -----------------------------------------------------------------------------
# 3. TTP (Tensor Transaction Protocol) 地址配置
# -----------------------------------------------------------------------------
if [[ "${RANK}" -eq 0 ]]; then
  # Rank 0 使用自身的 Pod IP
  export TTP_ADDR=${POD_IP:-"127.0.0.1"}
else
  # 其他 Rank 使用 Master 节点的 IP
  export TTP_ADDR=${MASTER_ADDR:-"127.0.0.1"}
fi

echo "TTP_PORT: ${TTP_PORT}"
echo "TTP_ADDR: ${TTP_ADDR}"

# -----------------------------------------------------------------------------
# 4. 设备与节点计数计算
# -----------------------------------------------------------------------------
if [[ "${LOCAL_WORLD_SIZE}" == "" ]]; then
    device_count=1
    server_count=1
else
    # 获取环境变量中的device_count字段
    device_count=${LOCAL_WORLD_SIZE}
    if [[ "${device_count}" -eq 0 ]]; then
      echo "device_count is 0, train job failed." | tee -a hccl.log
      # 如果 output_url 存在，尝试修改权限
      if [ -n "${output_url}" ]; then
        chmod 440 ${output_url}
      fi
      exit 1
    fi

    # 获取环境变量中的 server_count 字段
    server_count=`expr ${WORLD_SIZE} / ${device_count}`
    if [[ "${server_count}" == "" ]]; then
      echo "server_count is 0, train job failed." | tee -a hccl.log
      if [ -n "${output_url}" ]; then
        chmod 440 ${output_url}
      fi
      exit 1
    fi
fi

# 导出兼容旧脚本的变量名
export device_count
export server_count

# 导出通用的变量名 (供 torchrun 使用)
export NPROC_PER_NODE=$device_count
export NPUS_PER_NODE=$device_count
export NNODES=$server_count

echo "Environment setup complete."
echo "Device Count (NPROC_PER_NODE): $device_count"
echo "Server Count (NNODES): $server_count"
