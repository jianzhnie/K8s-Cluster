#!/bin/bash

unset PYTHONPATH

export HF_ENDPOINT=https://hf-mirror.com

# conda
# source /home/fdd/workspace/miniconda3/bin/activate mindspeed_llm_0105
source ~./bashrc

# cann 相关环境
# install_path=/home/fdd/workspace/Ascend/CANN8.3.RC1
# source $install_path/ascend-toolkit/set_env.sh
# source $install_path/nnal/atb/set_env.sh

# 日志相关
export ASCEND_SLOG_PRINT_TO_STDOUT=0
export ASCNED_GLOBAL_LOG_LEVEL=3
export MINDIE_LOG_TO_STDOUT=1
export ASDOPS_LOG_TO_STDOUT=1

# Torch 相关
export ASCEND_LAUNCH_BLOCKING=0
export TASK_QUEUE_ENABLE=2
export MULTI_STREAM_MEMORY_REUSE=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export COMBINED_ENABLE=1
export CPU_AFFINITY_CONF=1
# 以支持torch2.5以上版本
export TORCH_COMPILE_DEBUG=1
export TORCHDYNAMO_DISABLE=1

# ATB 相关
export ATB_LLM_BENCHMARK_ENABLE=1
export ATB_MATMUL_SHUFFLE_K_ENABLE=false
export ATB_LLM_LCOC_ENABLE=false

# vllm相关
export VLLM_RPC_GET_DATA_TIMEOUT_MS=1800000000
export VLLM_ALLOW_LONG_MAX_MODEL_LEN=1

# HCCL相关
export HCCL_BUFFSIZE=400
export HCCL_DETERMINISTIC=true
export HCCL_OP_BASE_FFTS_MODE_ENABLE=TRUE
export NCCL_TIMEOUT=12000000  # For NVIDIA
export HCCL_CONNECT_TIMEOUT=3600 # For Ascend (MindSpeed)
export HCCL_ALGO="alltoall=level0:NA;level1:pipeline"


# ray 相关
export RAY_DEDUP_LOGS=0
export GLOO_SOCKET_IFNAME=enp66s0f0
export HCCL_SOCKET_IFNAME=enp66s0f0
export CUDA_DEVICE_MAX_CONNECTIONS=1
export NPU_ASD_ENABLE=0
export STREAMS_PER_DEVICE=32


# PYTHONPATH 环境变量
if [ -z "$CURR_PROJECT_PATH" ]; then
    export CURR_PROJECT_PATH=$(pwd)
    echo "CURR_PROJECT_PATH was not set, setting it to current directory: $CURR_PROJECT_PATH"
else
    echo "CURR_PROJECT_PATH: $CURR_PROJECT_PATH"
fi
