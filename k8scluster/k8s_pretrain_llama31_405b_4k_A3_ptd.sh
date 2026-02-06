#!/bin/bash

# =============================================================================
# Llama3.1 405B 4K Training Start Script
# 依赖 k8s_common_env.sh 进行基础环境初始化
# =============================================================================

# 引用公共环境脚本
# source $(dirname "$0")/k8s_common_env.sh
source ~/.bashrc

mkdir -p /job/code/alllogs/$MINDX_TASK_ID/ttplogs
mkdir -p /job/code/alllogs/$MINDX_TASK_ID/trainlogs
mkdir -p /job/data/output/ckpt

# env for breakpoint ckpt
export RESUME_MODE_ENABLE=1

export ASCEND_GLOBAL_LOG_LEVEL=2                                                    # 设置plog等级为info，应根据实际需要设计等级
# 日志保存路径可根据实际情况修改
export ASCEND_PROCESS_LOG_PATH=/job/code/alllogs/$MINDX_TASK_ID/plogs/$XDL_IP       # 设置plog保存路径，其中$MINDX_TASK_ID为ascend-operator注入的任务uid环境变量，$XDL_IP为任务yaml中写入的环境变量，status.hostIP
export TTP_LOG_PATH=/job/code/alllogs/$MINDX_TASK_ID/ttplogs/ttplog$XDL_IP-$RANK    # 设置ttp日志保存路径，其中$RANK为ascend-operator为pytorch框架注入的环境变量
export TRAIN_LOG_PATH=/job/code/alllogs/$MINDX_TASK_ID/trainlogs/$XDL_IP-$RANK      # 设置训练日志保存路径

export HCCL_ASYNC_ERROR_HANDLING=0                 # 当HCCL_ASYNC_ERROR_HANDLING为0时，表示关闭watchdog功能。如果开启watchdog功能，可能会影响进程级恢复的正常使用。
export HCCL_WHITELIST_DISABLE=1
export GLOO_SOCKET_IFNAME=enp66s0f0               # 物理机上可以通信的网口，根据主节点高速网卡实际情况进行配置，如任务yaml中配置hostNetwork为false，则设置为eth0
export HCCL_SOCKET_IFNAME=enp66s0f0               # 如任务yaml中配置hostNetwork为false，则设置为eth0
export TTP_OT=360

export CUDA_DEVICE_MAX_CONNECTIONS=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export HCCL_CONNECT_TIMEOUT=3600
export HCCL_BUFFSIZE=256
export TASK_QUEUE_ENABLE=2
export NPU_ASD_ENABLE=0


# =============================================================================
# Llama3.1 405B 4K Training Paths
# =============================================================================

CKPT_SAVE_DIR="/job/data/output/ckpt"
DATA_PATH="/job/data/datasets/part00_text_document"
TOKENIZER_PATH="/job/data/models/LLM-Research/Meta-Llama-3.1-405B"
CKPT_LOAD_DIR="/job/data/models/LLM-Research/Meta-Llama-3.1-405B"


if [[ "${RANK}" -eq 0 ]]; then                     # 判断是否是rank,如是则设置其pod_ip为TTP_ADDR
  export TTP_ADDR=$POD_IP
else
  export TTP_ADDR=$MASTER_ADDR                     # 集群主节点的IP地址
fi
echo ${TTP_PORT}
echo ${TTP_ADDR}

if [[ "${LOCAL_WORLD_SIZE}" == "" ]]; then
    device_count=1
    server_count=1
else
    # 获取环境变量中的device_count字段
    device_count=${LOCAL_WORLD_SIZE}
    if [[ "${device_count}" -eq 0 ]]; then
      echo "device count is 0, train job failed." | tee -a hccl.log
      chmod 440 ${output_url}
      exit 1
    fi
    # 获取环境变量中的server_count字段
    server_count=`expr ${WORLD_SIZE} / ${LOCAL_WORLD_SIZE}`
    if [[ "${server_count}" == "" ]]; then
      echo "server count is 0, train job failed." | tee -a hccl.log
      chmod 440 ${output_url}
      exit 1
    fi
fi



# =============================================================================
# Llama3.1 405B 4K Training Hyperparameters
# =============================================================================

TP=16
PP=8
VPP=4
CP=2
CP_TYPE='megatron_cp_algo'
NUM_LAYERS=128
SEQ_LEN=2048
MBS=1
GBS=128

DISTRIBUTED_ARGS="
    --nproc_per_node $LOCAL_WORLD_SIZE \
    --nnodes $server_count \
    --node_rank $RANK \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT
"

OPTIMIZE_ARGS="
    --use-flash-attn \
    --use-fused-swiglu \
    --use-fused-rotary-pos-emb \
    --use-distributed-optimizer \
    --swap-attention \
    --reuse-fp32-param \
    --use-cp-send-recv-overlap \
    --use-fused-ring-attention-update \
    --tp-2d \
    --tp-x 8 \
    --tp-y 2 \
    --overlap-grad-reduce \
    --overlap-param-gather \
"

MODEL_PARALLEL_ARGS="
    --tensor-model-parallel-size ${TP} \
    --pipeline-model-parallel-size ${PP} \
    --num-layers-per-virtual-pipeline-stage ${VPP} \
    --context-parallel-size ${CP} \
    --context-parallel-algo megatron_cp_algo \
"

GPT_ARGS="
    --use-mcore-models \
    --num-layers ${NUM_LAYERS} \
    --hidden-size 16384 \
    --ffn-hidden-size 53248 \
    --num-attention-heads 128 \
    --disable-bias-linear \
    --group-query-attention \
    --num-query-groups 16 \
    --rope-scaling-type llama3 \
    --rope-scaling-factor 8.0 \
    --low-freq-factor 1.0 \
    --high-freq-factor 4.0 \
    --seq-length ${SEQ_LEN} \
    --swiglu \
    --position-embedding-type rope \
    --rotary-base 500000 \
    --original-max-position-embeddings 8192 \
    --max-position-embeddings ${SEQ_LEN} \
    --normalization RMSNorm \
    --norm-epsilon 1e-5 \
    --untie-embeddings-and-output-weights \
    --no-gradient-accumulation-fusion \
    --tokenizer-type PretrainedFromHF \
    --tokenizer-name-or-path ${TOKENIZER_PATH} \
    --make-vocab-size-divisible-by 1 \
    --attention-dropout 0.0 \
    --hidden-dropout 0.0 \
    --no-masked-softmax-fusion \
    --attention-softmax-in-fp32 \
    --bf16 \
"

TRAIN_ARGS="
    --micro-batch-size ${MBS} \
    --global-batch-size ${GBS} \
    --lr 1.0e-6 \
    --min-lr 1.0e-7 \
    --lr-decay-style cosine \
    --weight-decay 0.1 \
    --clip-grad 1.0 \
    --adam-beta1 0.9 \
    --adam-beta2 0.95 \
    --adam-eps 1e-5 \
    --initial-loss-scale 4096.0 \
    --init-method-std 0.01 \
"

DATA_ARGS="
    --data-path $DATA_PATH \
    --split 949,50,1 \
    --no-shared-storage \
"

CKPT_ARGS="
    --load ${CKPT_LOAD_DIR} \
    --no-load-optim \
    --no-load-rng \
    --no-save-optim \
    --no-save-rng \
    --save ${CKPT_SAVE_DIR} \
"

OUTPUT_ARGS="
    --train-iters 2000 \
    --eval-iters 2000 \
    --save-interval 2000 \
    --eval-interval 1000 \
    --log-interval 1 \
    --log-throughput \
"
unset HIGH_AVAILABILITY

torchrun $DISTRIBUTED_ARGS pretrain_gpt.py \
    $GPT_ARGS \
    $OPTIMIZE_ARGS \
    $MODEL_PARALLEL_ARGS \
    $TRAIN_ARGS \
    $DATA_ARGS \
    $CKPT_ARGS \
    $OUTPUT_ARGS \
    --distributed-backend nccl \
    | tee ${TRAIN_LOG_PATH}


ST=${PIPESTATUS[0]}
if [[ ${ST} -ne 0 ]]; then
       logger "running job failed. exit code: ${ST}" | tee -a ${output_url}/log
      exit ${ST}
fi
