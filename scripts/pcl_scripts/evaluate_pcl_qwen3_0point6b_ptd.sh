#!/bin/bash

source ~/.bashrc

# The number of parameters is not aligned
export CUDA_DEVICE_MAX_CONNECTIONS=1

# please fill these path configurations
TOKENIZER_PATH="/llm_workspace_1P/robin/hfhub/models/moonshotai/Kimi-K2-Base"
CHECKPOINT="/llm_workspace_1P/robin/hfhub/output/ckpt/k8s_pretrain_qwen3_0point6b_4K_ptd_256_dies_v2"
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

echo "DATA_PATH", $DATA_PATH
# =============================================================================

# Change for multinode config
MASTER_ADDR=localhost
MASTER_PORT=6001
NNODES=1
NODE_RANK=0
NPUS_PER_NODE=8
WORLD_SIZE=$(($NPUS_PER_NODE*$NNODES))

TP=1
PP=1
EP=1
SEQ_LENGTH=4096

DISTRIBUTED_ARGS="
    --nproc_per_node $NPUS_PER_NODE \
    --nnodes $NNODES \
    --node_rank $NODE_RANK \
    --master_addr $MASTER_ADDR \
    --master_port $MASTER_PORT
"

torchrun $DISTRIBUTED_ARGS evaluation.py \
         --no-chat-template \
         --task-data-path ${DATA_PATH} \
         --task ${TASK} \
         --use-mcore-models \
         --tensor-model-parallel-size ${TP} \
         --pipeline-model-parallel-size ${PP} \
         --expert-model-parallel-size ${EP} \
         --load ${CHECKPOINT} \
         --spec mindspeed_llm.tasks.models.spec.qwen3_spec layer_spec \
         --kv-channels 128 \
         --qk-layernorm \
         --num-layers 28 \
         --hidden-size 1024 \
         --use-rotary-position-embeddings \
         --num-attention-heads 16 \
         --ffn-hidden-size 3072 \
         --max-position-embeddings 32768 \
         --seq-length ${SEQ_LENGTH} \
         --make-vocab-size-divisible-by 1 \
         --padded-vocab-size 163840 \
         --rotary-base 1000000 \
         --micro-batch-size 1 \
         --disable-bias-linear \
         --swiglu \
         --tokenizer-type PretrainedFromHF \
         --tokenizer-name-or-path ${TOKENIZER_PATH} \
         --normalization RMSNorm \
         --position-embedding-type rope \
         --norm-epsilon 1e-6 \
         --hidden-dropout 0 \
         --attention-dropout 0 \
         --max-new-tokens 2 \
         --no-gradient-accumulation-fusion \
         --attention-softmax-in-fp32 \
         --exit-on-missing-checkpoint \
         --no-masked-softmax-fusion \
         --group-query-attention \
         --num-query-groups 8 \
         --seed 42 \
         --bf16 \
         --transformer-impl local \
         | tee logs/evaluate_qwen3_0point6b.log
