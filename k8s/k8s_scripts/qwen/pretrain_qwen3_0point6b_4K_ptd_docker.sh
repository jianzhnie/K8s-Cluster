#!/bin/bash

source ~/.bashrc

# 环境变量配置
export HCCL_CONNECT_TIMEOUT=1800
export CUDA_DEVICE_MAX_CONNECTIONS=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export NPU_ASD_ENABLE=0
export TASK_QUEUE_ENABLE=2

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


# 数据路径配置, 模型路径配置
DATA_PATH="/llm_workspace_1P/robin/hfhub/datasets/tatsu-lab/alpaca/data/train-00000-of-00001-a09b74b3ef9c3b56.parquet"
TOKENIZER_PATH="/llm_workspace_1P/robin/hfhub/models/moonshotai/Kimi-K2-Base"
CKPT_LOAD_DIR="/llm_workspace_1P/robin/hfhub/models/Qwen/Qwen3-0.6B"
DATA_PREFIX_FILE="/llm_workspace_1P/robin/K8s-Cluster/scripts/data_prefixes.txt"
DATA_DIR="/llm_workspace_1P/fdd/workspace/datasets/C3_LVM/all_preprocessed_datasets"
DATA_NAME_PATTERN="part*"

OUTPUT_DIR="/llm_workspace_1P/robin/MindSpeed-LLM/work_dir/pretrain_qwen3_8b_4K_ptd_A3"
DATETIME=$(date +%Y-%m-%d_%H-%M-%S)
LOG_DIR="$OUTPUT_DIR/logs/$DATETIME"
CKPT_SAVE_DIR="$OUTPUT_DIR/model_ckpt"
MG_SAVE_DIR="$CKPT_SAVE_DIR/mcore"
HF_SAVE_DIR="$CKPT_SAVE_DIR/hf"


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
    printf "[INFO] 从文件加载到 %d 个数据前缀\\n" "${#DATA_FILES_LIST[@]}"
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
NPUS_PER_NODE=8
MASTER_ADDR=localhost
MASTER_PORT=6011
NNODES=1
NODE_RANK=0
WORLD_SIZE=$(($NPUS_PER_NODE*$NNODES))


TP=1
PP=1
MBS=4
GBS=1024
SEQ_LENGTH=4096
TRAIN_ITERS=2000
SAVE_ITERS=1000

DISTRIBUTED_ARGS="
    --nproc_per_node $NPUS_PER_NODE \
    --nnodes $NNODES \
    --node_rank $NODE_RANK \
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
    --overlap-param-gather \
    --gemm-gradient-accumulation-fusion
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
    --split 100,0,0 \
    --save $CKPT_SAVE_DIR \
"

OUTPUT_ARGS="
    --log-interval 1 \
    --log-throughput \
    --save-interval ${SAVE_ITERS} \
    --eval-interval ${SAVE_ITERS} \
    --eval-iters 0 \
"

torchrun $DISTRIBUTED_ARGS pretrain_gpt.py \
    $GPT_ARGS \
    $TRAIN_FROM_MG \
    $OUTPUT_ARGS \
    $OPTIMIZE_ARGS \
    $TRAIN_ARGS \
    $MODEL_PARALLEL_ARGS \
    --distributed-backend nccl \
    --transformer-impl local
