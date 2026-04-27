#!/bin/bash
source ~/.bashrc

# -----------------------------------------------------------------------------
# 1. 基础变量检查与设置
# -----------------------------------------------------------------------------
# 检查关键环境变量，缺失则报错
: "${RANK:?RANK is required}"
: "${WORLD_SIZE:?WORLD_SIZE is required}"
: "${MINDX_TASK_ID:?MINDX_TASK_ID is required}"
: "${XDL_IP:?XDL_IP is required}"

OUTPUT_DIR="/llm_workspace_1P/robin/hfhub/output"
DATETIME=$(date +%Y-%m-%d_%H-%M-%S)
SCRIPT_NAME=$(basename "$0")
SCRIPT_PREFIX="${SCRIPT_NAME%.sh}"
START_SCRIPT="/llm_workspace_1P/robin/MindSpeed-LLM/scripts/${SCRIPT_NAME}"

# 日志与Checkpoint目录配置
LOG_DIR="$OUTPUT_DIR/logs/${SCRIPT_PREFIX}_${WORLD_SIZE}_dies/${MINDX_TASK_ID}"
CKPT_SAVE_DIR="$OUTPUT_DIR/ckpt/${SCRIPT_PREFIX}_${WORLD_SIZE}_dies_v2/"

# Rank 0 负责创建目录并备份脚本
if [[ "${RANK}" -eq 0 ]]; then
    echo "Initializing directories at $LOG_DIR"
    mkdir -p "$LOG_DIR/plogs"
    mkdir -p "$LOG_DIR/ttplogs"
    mkdir -p "$LOG_DIR/trainlogs"
    mkdir -p "$CKPT_SAVE_DIR"

    # Try to copy the script file to the log directory
    if [[ -f "$0" ]]; then
        cp "$0" "$LOG_DIR/"
    else
        echo "Warning: Could not find script file at $0 to copy, try to copy $START_SCRIPT instead."
        cp "$START_SCRIPT" "$LOG_DIR/"
    fi
    printenv > "$LOG_DIR/env_vars.sh"
fi

# 定义具体的日志路径
rm -rf /root/.cache/
export ASCEND_PROCESS_LOG_PATH="$LOG_DIR/plogs/rank-${RANK}_${XDL_IP}"
export TTP_LOG_PATH="$LOG_DIR/ttplogs/rank-${RANK}_${XDL_IP}"
export TRAIN_LOG_PATH="$LOG_DIR/trainlogs/rank-${RANK}_${XDL_IP}.log"

# -----------------------------------------------------------------------------
# 2. 训练环境与网络配置
# -----------------------------------------------------------------------------
export RESUME_MODE_ENABLE=1
export ASCEND_GLOBAL_LOG_LEVEL=3
export HCCL_ASYNC_ERROR_HANDLING=0
export HCCL_WHITELIST_DISABLE=1
export GLOO_SOCKET_IFNAME=enp66s0f0                # 物理机上可以通信的网口，根据主节点高速网卡实际情况进行配置，如任务yaml中配置hostNetwork为false，则设置为eth0
export HCCL_SOCKET_IFNAME=enp66s0f0                # 如任务yaml中配置hostNetwork为false，则设置为eth0

export TTP_OT=360
export CUDA_DEVICE_MAX_CONNECTIONS=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export HCCL_CONNECT_TIMEOUT=3600
export HCCL_BUFFSIZE=400
export TASK_QUEUE_ENABLE=2
export NPU_ASD_ENABLE=0
export STREAMS_PER_DEVICE=32
export HCCL_OP_BASE_FFTS_MODE=TRUE
export HCCL_ALGO="alltoall=level0:NA;level1:pipeline"


# =============================================================================
# 加载自定义OP 并等待加载完成，提前加载可以减少算子编译时间，避免训练过程中动态编译算子导致的性能问题
# 自定义OP 加载顺序：GMMOpBuilder, GMMV2OpBuilder, MatmulAddOpBuilder, MoeTokenPermuteOpBuilder, MoeTokenUnpermuteOpBuilder,
#                 RotaryPositionEmbeddingOpBuilder, GroupMatmulAddOpBuilder
rm -rf /root/.cache/torch_extensions/py310_cpu/
python -c "import mindspeed; from mindspeed.op_builder import GMMOpBuilder; GMMOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import GMMV2OpBuilder; GMMV2OpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MatmulAddOpBuilder; MatmulAddOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MoeTokenPermuteOpBuilder; MoeTokenPermuteOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MoeTokenUnpermuteOpBuilder; MoeTokenUnpermuteOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import RotaryPositionEmbeddingOpBuilder; RotaryPositionEmbeddingOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import GroupMatmulAddOpBuilder; GroupMatmulAddOpBuilder().load()"
# =============================================================================


MG_SAVE_DIR="$CKPT_SAVE_DIR/mcore"
HF_SAVE_DIR="$CKPT_SAVE_DIR/hf"

# 数据路径配置, 模型路径配置
TOKENIZER_PATH="/llm_workspace_1P/robin/hfhub/models/moonshotai/Kimi-K2-Base"
CKPT_LOAD_DIR="$OUTPUT_DIR/ckpt/${SCRIPT_PREFIX}_${WORLD_SIZE}_dies/"
DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/benchmark/mmlu/test/"
TASK="mmlu"

# ===================== ========================================================
# 任务配置
DEFAULT_DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/benchmark/mmlu/test"
DEFAULT_MAX_NEW_TOKEN=32

case "$TASK" in
    "mmlu")
        DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/benchmark/mmlu/test"
        MAX_NEW_TOKEN=2
        ;;
    "bbh")
        DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/benchmark/bbh/"
        MAX_NEW_TOKEN=32
        ;;
    "human-eval")
        DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/benchmark/human-eval"
        MAX_NEW_TOKEN=1024
        ;;
    "gsm8k")
        DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/benchmark/gsm8k"
        MAX_NEW_TOKEN=512
        ;;
    *)
        # 匹配到未知 TASK 值时的容错处理
        echo "警告：未知的 TASK 值 '$TASK'，使用默认路径"
        DATA_PATH=${DEFAULT_DATA_PATH}
        MAX_NEW_TOKEN=${DEFAULT_MAX_NEW_TOKEN}
        ;;
esac

echo "TASK=${TASK}"
echo "DATA_PATH=${DATA_PATH}"
echo "MAX_NEW_TOKEN=${MAX_NEW_TOKEN}"
echo "TOKENIZER_PATH=${TOKENIZER_PATH}"
echo "CKPT_LOAD_DIR=${CKPT_LOAD_DIR}"
# =============================================================================

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
      if [[ -n "${output_url:-}" ]]; then chmod 440 "${output_url}"; fi
      exit 1
    fi
    # 获取环境变量中的server_count字段
    server_count=`expr ${WORLD_SIZE} / ${LOCAL_WORLD_SIZE}`
    if [[ "${server_count}" == "" ]]; then
      echo "server count is 0, train job failed." | tee -a hccl.log
      if [[ -n "${output_url:-}" ]]; then chmod 440 "${output_url}"; fi
      exit 1
    fi
fi



# Change for multinode config

TP=2
PP=8
EP=8
SEQ_LENGTH=4096
CP_TYPE='ulysses_cp_algo'
NUM_LAYERS=32
SEQ_LEN=4096
MBS=1


DISTRIBUTED_ARGS="
    --nproc_per_node $LOCAL_WORLD_SIZE \
    --nnodes $server_count \
    --node_rank $RANK \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT
"

MOE_ARGS="
    --moe-shared-expert-overlap \
    --moe-grouped-gemm \
    --moe-token-dispatcher-type alltoall \
    --use-fused-moe-token-permute-and-unpermute \
    --moe-permutation-async-comm \
    --first-k-dense-replace 2 \
    --moe-layer-freq 1 \
    --n-shared-experts 1 \
    --num-experts 128 \
    --moe-router-topk 2 \
    --moe-ffn-hidden-size 12288 \
    --moe-router-load-balancing-type aux_loss \
    --moe-router-num-groups 8 \
    --moe-router-group-topk 2 \
    --moe-router-topk-scaling-factor 2.827 \
    --seq-aux \
    --norm-topk-prob \
    --moe-router-score-function sigmoid \
    --moe-router-enable-expert-bias \
    --moe-router-dtype fp32 \
    --moe-expert-capacity-factor 2.0 \
    --moe-pad-expert-input-to-capacity \
"

BALANCE_ARGS="
    --balanced-moe-experts \
"

GQA_ARGS="
    --kv-channels 128 \
    --qk-layernorm \
    --num-attention-heads 64 \
    --num-query-groups 2 \
    --group-query-attention \
"

ROPE_ARGS="
    --beta-fast 1 \
    --beta-slow 1 \
    --rope-scaling-factor 32 \
    --rope-scaling-mscale 1.0 \
    --rope-scaling-mscale-all-dim  1.0 \
    --rope-scaling-original-max-position-embeddings 4096 \
    --rope-scaling-type yarn

"
GPT_ARGS="
    --spec mindspeed_llm.tasks.models.spec.qwen3_spec layer_spec \
    --gemm-gradient-accumulation-fusion \
    --moe-zero-memory level0 \
    --expert-tensor-parallel-size 1 \
    --no-shared-storage \
    --use-flash-attn \
    --use-mcore-models \
    --tensor-model-parallel-size ${TP} \
    --pipeline-model-parallel-size ${PP} \
    --expert-model-parallel-size ${EP} \
    --sequence-parallel \
    --context-parallel-size ${CP} \
    --context-parallel-algo  ${CP_TYPE} \
    --num-layers ${NUM_LAYERS} \
    --hidden-size 7168 \
    --ffn-hidden-size 18432 \
    --tokenizer-type PretrainedFromHF  \
    --tokenizer-name-or-path ${TOKENIZER_PATH} \
    --seq-length ${SEQ_LEN} \
    --max-position-embeddings 131072 \
    --micro-batch-size ${MBS} \
    --global-batch-size ${GBS} \
    --make-vocab-size-divisible-by 1 \
    --untie-embeddings-and-output-weights \
    --use-fused-rotary-pos-emb \
    --use-rotary-position-embeddings \
    --use-fused-swiglu \
    --use-fused-rmsnorm \
    --disable-bias-linear \
    --attention-dropout 0.0 \
    --init-method-std 0.02 \
    --hidden-dropout 0.0 \
    --position-embedding-type rope \
    --normalization RMSNorm \
    --use-rotary-position-embeddings \
    --swiglu \
    --no-masked-softmax-fusion \
    --attention-softmax-in-fp32 \
    --initial-loss-scale 65536 \
    --vocab-size 163840 \
    --padded-vocab-size 163840 \
    --rotary-base 50000 \
    --norm-epsilon 1e-6 \
    --seed 2233 \
    --bf16 \
    --broadcast \
    --distributed-timeout-minutes 120 \
"


EVAL_ARGS="
    --task ${TASK} \
    --task-data-path ${DATA_PATH} \
    --load ${CKPT_LOAD_DIR} \
    --no-load-optim \
    --no-load-rng \
    --max-new-tokens ${MAX_NEW_TOKEN} \
    --no-chat-template \
    --use-kv-cache \
    --evaluation-batch-size 1 \
"

unset HIGH_AVAILABILITY

torchrun $DISTRIBUTED_ARGS evaluation.py \
    $GPT_ARGS \
    $GQA_ARGS \
    $ROPE_ARGS \
    $MOE_ARGS \
    $EVAL_ARGS \
    --distributed-backend nccl \
    --transformer-impl local \
    2>&1 | tee ${TRAIN_LOG_PATH}
