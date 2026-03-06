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

OUTPUT_DIR="/job/data/output"
DATETIME=$(date +%Y-%m-%d_%H-%M-%S)
SCRIPT_NAME=$(basename "$0")
SCRIPT_PREFIX="${SCRIPT_NAME%.sh}"
STRART_SCRIPT="/job/code/scripts/${SCRIPT_NAME}"

# 日志与Checkpoint目录配置
LOG_DIR="$OUTPUT_DIR/logs/${SCRIPT_PREFIX}_${WORLD_SIZE}_dies/${MINDX_TASK_ID}"
CKPT_SAVE_DIR="$OUTPUT_DIR/ckpt/${SCRIPT_PREFIX}_${WORLD_SIZE}_dies/"

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
        echo "Warning: Could not find script file at $0 to copy, try to copy $STRART_SCRIPT instead."
        cp "$STRART_SCRIPT" "$LOG_DIR/"
    fi
    printenv > "$LOG_DIR/env_vars.sh"
else
    # 其他节点等待 Rank 0 创建目录 (Wait until directory exists)
    echo "Waiting for directory initialization..."
    for i in {1..10}; do
        if [[ -d "$LOG_DIR/trainlogs" ]]; then
            echo "Directory found."
            break
        fi
        sleep 6
    done
fi

# 定义具体的日志路径
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
export TASK_QUEUE_ENABLE=1
export NPU_ASD_ENABLE=0
export STREAMS_PER_DEVICE=32
export HCCL_OP_BASE_FFTS_MODE=TRUE
export HCCL_ALGO="alltoall=level0:NA;level1:pipeline"


# =============================================================================
# 加载自定义OP 并等待加载完成，提前加载可以减少算子编译时间，避免训练过程中动态编译算子导致的性能问题
# 自定义OP 加载顺序：GMMOpBuilder, GMMV2OpBuilder, MatmulAddOpBuilder, MoeTokenPermuteOpBuilder, MoeTokenUnpermuteOpBuilder,
#                 RotaryPositionEmbeddingOpBuilder, GroupMatmulAddOpBuilder
python -c "import mindspeed; from mindspeed.op_builder import GMMOpBuilder; GMMOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import GMMV2OpBuilder; GMMV2OpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MatmulAddOpBuilder; MatmulAddOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MoeTokenPermuteOpBuilder; MoeTokenPermuteOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MoeTokenUnpermuteOpBuilder; MoeTokenUnpermuteOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import RotaryPositionEmbeddingOpBuilder; RotaryPositionEmbeddingOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import GroupMatmulAddOpBuilder; GroupMatmulAddOpBuilder().load()"
# =============================================================================

CKPT_SAVE_DIR="/job/data/output/ckpt"
MG_SAVE_DIR="$CKPT_SAVE_DIR/mcore"
HF_SAVE_DIR="$CKPT_SAVE_DIR/hf"

# 数据路径配置, 模型路径配置
DATA_PATH="/job/data/datasets/tatsu-lab/alpaca/data/train-00000-of-00001-a09b74b3ef9c3b56.parquet"
TOKENIZER_PATH="/job/data/models/moonshotai/Kimi-K2-Base"
CKPT_LOAD_DIR="/job/data/models/Qwen/Qwen3-0.6B"

DATA_PREFIX_FILE="/job/data/datasets/data_prefixes.txt"
DATA_DIR="/job/fdd/datasets/C3_LVM/all_preprocessed_datasets"
DATA_NAME_PATTERN="part*"
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



# Auto-discover data paths (populate no_ext_files array)
discover_data_prefixes() {
    local data_dir="$1"
    local pattern="$2"
    local -n out_array=$3   # nameref for returning the array

    echo "[INFO] 正在从 DATA_DIR='$data_dir' 和 PATTERN='$pattern' 自动发现数据文件..."
    mapfile -t out_array < <(
        find "$data_dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null \
        | sed 's/\.[^.]*$//' \
        | sort -u
    )

    if [ ${#out_array[@]} -eq 0 ]; then
        echo "[ERROR] 未在 '$data_dir' 中找到匹配 '$pattern' 的文件！"
        return 1
    fi

    echo "[INFO] 发现以下去重后的数据前缀（已去除 .bin/.idx 后缀）:"
    printf '  - %s\n' "${out_array[@]}"
    return 0
}

# Auto-discover data paths (populate no_ext_files array)
load_data_prefixes_from_file() {
    local file="$1"
    mapfile -t DATA_FILES_LIST < <(grep -v -e '^\s*$' -e '^\s*#' "$file" 2>/dev/null | sed 's/[[:space:]]*$//' )
    if [ ${#DATA_FILES_LIST[@]} -eq 0 ]; then
        return 1
    fi
    printf "[INFO] 从文件加载到 %d 个数据路径\\n" "${#DATA_FILES_LIST[@]}"
    for p in "${DATA_FILES_LIST[@]}"; do
        printf "  - %s\n" "$p"
    done

    return 0
}

prepare_data_prefixes() {
    if [ -n "${DATA_PREFIX_FILE:-}" ] && [ -f "$DATA_PREFIX_FILE" ]; then
        if load_data_prefixes_from_file "$DATA_PREFIX_FILE"; then
            DATA_PREFIXES="${DATA_FILES_LIST[*]}"
            echo "[INFO] 自动生成的数据集前缀列表 (From File): $DATA_PREFIXES"
            return 0
        fi
    fi
    if ! discover_data_prefixes "$DATA_DIR" "$DATA_NAME_PATTERN" DATA_FILES_LIST; then
        return 1
    fi
    echo "[INFO] DATA_FILES_LIST: ${DATA_FILES_LIST[*]}"
    # 将数组拼接为 Python 列表格式的字符串 (['path1','path2',...])
    # 1. 使用 printf 给每个元素加上单引号
    local quoted_list=()
    for item in "${DATA_FILES_LIST[@]}"; do
        quoted_list+=("'$item'")
    done

    # 2. 使用 IFS=, 将带引号的元素拼接
    local joined_items=$(IFS=,; echo "${quoted_list[*]}")

    # 3. 直接赋值数组元素，不需要方括号
    DATA_PREFIXES="${DATA_FILES_LIST[*]}"
    echo "[INFO] 自动生成的数据集前缀列表 (Python List Format): $DATA_PREFIXES"
    return 0
}



# 自动发现数据集前缀
if ! prepare_data_prefixes; then
    echo "[ERROR] 数据前缀发现失败，无法继续训练！"
    exit 1
fi


# 训练参数配置
# =============================================================================

TP=1
PP=1
MBS=4
GBS=8192
SEQ_LENGTH=4096
TRAIN_ITERS=2000
SAVE_ITERS=1000

DISTRIBUTED_ARGS="
    --nproc_per_node $LOCAL_WORLD_SIZE \
    --nnodes $server_count \
    --node_rank $RANK \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT
"

OPTIMIZE_ARGS="
    --use-flash-attn \
    --use-fused-rotary-pos-emb \
    --use-rotary-position-embeddings \
    --use-fused-swiglu \
    --use-fused-rmsnorm \
    --no-masked-softmax-fusion \
    --use-distributed-optimizer \
    --overlap-grad-reduce \
    --overlap-param-gather
"

MODEL_PARALLEL_ARGS="
    --tensor-model-parallel-size ${TP} \
    --pipeline-model-parallel-size ${PP} \
"

TRAIN_ARGS="
    --micro-batch-size ${MBS} \
    --global-batch-size ${GBS} \
    --lr 1.25e-6 \
    --min-lr 1.25e-7 \
    --weight-decay 1e-1 \
    --attention-dropout 0.0 \
    --hidden-dropout 0.0 \
    --clip-grad 1.0 \
    --adam-beta1 0.9 \
    --adam-beta2 0.95 \
    --initial-loss-scale 4096 \
    --seed 42 \
    --bf16 \
    --train-iters ${TRAIN_ITERS} \
    --seq-length ${SEQ_LENGTH} \
    --no-shared-storage
"

GPT_ARGS="
    --use-mcore-models \
    --sequence-parallel \
    --spec mindspeed_llm.tasks.models.spec.qwen3_spec layer_spec \
    --kv-channels 128 \
    --qk-layernorm \
    --num-layers 28 \
    --hidden-size 1024 \
    --num-attention-heads 16 \
    --ffn-hidden-size 3072 \
    --max-position-embeddings 32768 \
    --make-vocab-size-divisible-by 1 \
    --padded-vocab-size 163840 \
    --rotary-base 1000000 \
    --disable-bias-linear \
    --swiglu \
    --tokenizer-type PretrainedFromHF \
    --tokenizer-name-or-path ${TOKENIZER_PATH} \
    --normalization RMSNorm \
    --position-embedding-type rope \
    --norm-epsilon 1e-6 \
    --no-gradient-accumulation-fusion \
    --attention-softmax-in-fp32 \
    --exit-on-missing-checkpoint \
    --group-query-attention \
    --num-query-groups 8 \
    --no-load-optim \
    --no-load-rng \
    --seed 42 \
    --bf16
"

DATA_ARGS="
    --data-path $DATA_PATH \
    --split 100,0,0
"

TRAIN_FROM_HF="
    --data-path $DATA_PATH \
    --split 100,0,0 \
    --enable-hf2mg-convert \
    --model-type-hf qwen3 \
    --save $CKPT_SAVE_DIR \
    --mg-save-dir $MG_SAVE_DIR \
    --prompt-type qwen3 \
"

TRAIN_FROM_MG="
    --data-path $DATA_PREFIXES \
    --num-dataset-builder-threads 4 \
    --data-cache-path $CKPT_SAVE_DIR/cache/megatron_indices \
    --split 100,0,0 \
    --save $CKPT_SAVE_DIR \
    --manual-gc \
    --manual-gc-interval 50 \
"

OUTPUT_ARGS="
    --log-interval 1 \
    --log-throughput \
    --save-interval ${SAVE_ITERS} \
    --eval-interval ${SAVE_ITERS} \
    --eval-iters 0 \
"

unset HIGH_AVAILABILITY
torchrun $DISTRIBUTED_ARGS pretrain_gpt.py \
    $GPT_ARGS \
    $TRAIN_FROM_MG \
    $OUTPUT_ARGS \
    $OPTIMIZE_ARGS \
    $TRAIN_ARGS \
    $MODEL_PARALLEL_ARGS \
    --distributed-backend nccl \
    --transformer-impl local \
    2>&1 | tee ${TRAIN_LOG_PATH}
