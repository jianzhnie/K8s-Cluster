#!/bin/bash

# =============================================================================
# Deepseek3 671B 4K Training Start Script
# 依赖 k8s_common_env.sh 进行基础环境初始化
# =============================================================================

# 引用公共环境脚本
# source $(dirname "$0")/k8s_common_env.sh
source ~/.bashrc

mkdir -p /job/code/alllogs/deepseek3_671b_4k/$MINDX_TASK_ID/ttplogs
mkdir -p /job/code/alllogs/deepseek3_671b_4k/$MINDX_TASK_ID/trainlogs
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
# Deepseek3 671B 4K Training Paths
# =============================================================================

CKPT_SAVE_DIR="/job/data/output/ckpt"
DATA_PATH="/job/data/datasets/nv_cc/300B/part_000000_deepseek32_671b_text_document"
# DATA_PATH="/job/data/datasets/alpaca/alpaca_text_document"
TOKENIZER_PATH="/job/data/models/deepseek-ai/DeepSeek-V3-Base"
CKPT_LOAD_DIR="/job/data/models/deepseek-ai/DeepSeek-V3-Base"


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
# Deepseek3 671B 4K Training Hyperparameters
# =============================================================================

TP=2
PP=8
EP=32
CP=1
CP_TYPE='ulysses_cp_algo'
NUM_LAYERS=64
SEQ_LEN=4096
MBS=1
GBS=3840

DISTRIBUTED_ARGS="
    --nproc_per_node $LOCAL_WORLD_SIZE \
    --nnodes $server_count \
    --node_rank $RANK \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT
"

MLA_ARGS="
    --multi-latent-attention \
    --qk-pos-emb-head-dim 64 \
    --qk-head-dim 128 \
    --q-lora-rank 1536 \
    --kv-lora-rank 512 \
    --v-head-dim 128 \
    --qk-layernorm \
    --mla-mm-split \
    --mla-fa-without-pad \
"

MOE_ARGS="
    --moe-grouped-gemm \
    --moe-permutation-async-comm \
    --moe-token-dispatcher-type alltoall \
    --moe-permute-fusion \
    --first-k-dense-replace 3 \
    --moe-layer-freq 1 \
    --moe-shared-expert-intermediate-size 2048 \
    --num-experts 256 \
    --moe-router-topk 8 \
    --moe-ffn-hidden-size 2048 \
    --moe-router-load-balancing-type none \
    --moe-router-num-groups 8 \
    --moe-router-group-topk 4 \
    --moe-router-topk-scaling-factor 2.5 \
    --moe-aux-loss-coeff 0.0001 \
    --seq-aux \
    --moe-router-score-function sigmoid \
    --moe-router-enable-expert-bias \
    --moe-router-dtype fp32 \
"

MTP_ARGS="
    --mtp-num-layers 1 \
    --mtp-loss-scaling-factor 0.3 \
"

DUALPIPE_ARGS="
    --moe-fb-overlap \
    --schedules-method dualpipev \
"

MEM_ARGS="
    --mtp-mem-efficient-logits \
    --swap-optimizer \
    --recompute-granularity full \
    --recompute-method block \
    --recompute-num-layers 8 \
"

ROPE_ARGS="
    --beta-fast 32 \
    --beta-slow 1 \
    --rope-scaling-factor 40 \
    --rope-scaling-mscale 1.0 \
    --rope-scaling-mscale-all-dim 1.0 \
    --rope-scaling-original-max-position-embeddings 4096 \
    --rope-scaling-type yarn
"


GPT_ARGS="
    --transformer-impl local \
    --spec mindspeed_llm.tasks.models.spec.deepseek_spec layer_spec \
    --reset-attention-mask \
    --gemm-gradient-accumulation-fusion \
    --noop-layers 61,62,63 \
    --manual-gc \
    --manual-gc-interval 50 \
    --no-shared-storage \
    --use-distributed-optimizer \
    --use-flash-attn \
    --use-mcore-models \
    --tensor-model-parallel-size ${TP} \
    --pipeline-model-parallel-size ${PP} \
    --expert-model-parallel-size ${EP} \
    --expert-tensor-parallel-size 1 \
    --sequence-parallel \
    --context-parallel-size ${CP} \
    --context-parallel-algo  ${CP_TYPE} \
    --num-layers ${NUM_LAYERS} \
    --hidden-size 7168 \
    --ffn-hidden-size 18432 \
    --num-attention-heads 128 \
    --tokenizer-type PretrainedFromHF  \
    --tokenizer-name-or-path ${TOKENIZER_PATH} \
    --seq-length ${SEQ_LEN} \
    --max-position-embeddings 163840 \
    --micro-batch-size ${MBS} \
    --global-batch-size ${GBS} \
    --make-vocab-size-divisible-by 1 \
    --lr 1.0e-5 \
    --train-iters 2000 \
    --lr-decay-style cosine \
    --untie-embeddings-and-output-weights \
    --disable-bias-linear \
    --attention-dropout 0.0 \
    --init-method-std 0.02 \
    --hidden-dropout 0.0 \
    --position-embedding-type rope \
    --normalization RMSNorm \
    --use-fused-rotary-pos-emb \
    --use-rotary-position-embeddings \
    --use-fused-swiglu \
    --use-fused-rmsnorm \
    --swiglu \
    --no-masked-softmax-fusion \
    --attention-softmax-in-fp32 \
    --min-lr 1.0e-7 \
    --weight-decay 1e-2 \
    --lr-warmup-iters 500 \
    --clip-grad 1.0 \
    --adam-beta1 0.9 \
    --adam-beta2 0.999 \
    --initial-loss-scale 65536 \
    --vocab-size 129280 \
    --padded-vocab-size 129280 \
    --rotary-base 10000 \
    --norm-epsilon 1e-6 \
    --no-load-optim \
    --no-load-rng \
    --bf16 \
    --distributed-timeout-minutes 120 \
"

DATA_ARGS="
    --data-path $DATA_PATH \
    --split 100,0,0
"

OUTPUT_ARGS="
    --log-interval 1 \
    --log-throughput \
    --save-interval 2000 \
    --eval-interval 2000 \
    --eval-iters 0 \
    --no-save-optim \
    --no-save-rng
"

unset HIGH_AVAILABILITY

torchrun $DISTRIBUTED_ARGS pretrain_gpt.py \
    $GPT_ARGS \
    $DATA_ARGS \
    $OUTPUT_ARGS \
    $MLA_ARGS \
    $DUALPIPE_ARGS \
    $MEM_ARGS \
    $ROPE_ARGS \
    $MOE_ARGS \
    $MTP_ARGS \
    --distributed-backend nccl \
    | tee ${TRAIN_LOG_PATH}


ST=${PIPESTATUS[0]}
if [[ ${ST} -ne 0 ]]; then
       logger "running job failed. exit code: ${ST}" | tee -a ${output_url}/log
      exit ${ST}
fi
