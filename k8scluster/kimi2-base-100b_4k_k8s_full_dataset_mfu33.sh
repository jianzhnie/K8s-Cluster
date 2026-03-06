#!/bin/bash

# source /home/fdd/workspace/Ascend/CANN8.3.RC1/ascend-toolkit/set_env.sh;
# source /home/fdd/workspace/Ascend/CANN8.3.RC1/nnal/atb/set_env.sh;
# source /home/fdd/workspace/Ascend/CANN8.5.0/ascend-toolkit/set_env.sh
# source /home/fdd/workspace/Ascend/CANN8.5.0/nnal/atb/set_env.sh


# source /home/fdd/workspace/miniconda3/bin/activate mindspeed_llm_0227
source ~/.bashrc # 注意：这里会切换到镜像里面的/MindSpeed-LLM/MindSpeed-LLM目录
cd /home/fdd/workspace/MindSpeed-LLM-0227/MindSpeed-LLM

script_filename=$(basename "$0")
# 提取不带 .sh 后缀的前缀
script_prefix="${script_filename%.sh}"
# 构造 log_dir，使用提取出的前缀
log_dir=/home/ljj/workspace/TrainResults/${script_prefix}_${WORLD_SIZE}_dies

date=$MINDX_TASK_ID
log_dir=${log_dir}/$date
CKPT_SAVE_DIR=$log_dir
if [[ "${RANK}" -eq 0 ]]; then
    mkdir -p $log_dir
    cp "$0" "$log_dir"
else
    sleep 6s
fi


export ASCEND_GLOBAL_LOG_LEVEL=3
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


TOKENIZER_PATH=$1
CKPT_LOAD_DIR=$2
# DATA_GLOB_PATTERN=$3
# DATA_DIR="/home/fdd/workspace/datasets/C3_LVM/Nmath/3_Kimi-K2-Base"
DATA_DIR=$3
DATA_NAME_PATTERN="part*bin"


# Auto-discover data paths (populate no_ext_files array)
discover_data_prefixes() {
    local data_dir="$1"
    local pattern="$2"
    local -n out_array=$3   # nameref for returning the array

    echo "[INFO] 正在从 DATA_DIR='$data_dir' 和 PATTERN='$pattern' 自动发现数据文件..."
    mapfile -t out_array < <(
        find "$data_dir" -maxdepth 3 -name "$pattern" -type f 2>/dev/null \
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


prepare_data_prefixes() {
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

# echo "[INFO] 正在从 DATA_GLOB_PATTERN='$DATA_GLOB_PATTERN'自动发现数据文件..."
# files=($DATA_GLOB_PATTERN)
# for f in "${files[@]}"; do
#     if [[ -f "$f" ]]; then
#         dir=$(dirname "$f")
#         base=$(basename "$f" .bin)
#         full_path_no_ext="$dir/$base"
#         no_ext_files+=("$full_path_no_ext")
#     fi
# done
# echo "[INFO] 发现以下数据:"
# printf '  - %s\n' "${no_ext_files[@]}"
# # 构建安全转义的路径参数字符串（用于 SSH 命令）
# DATA_PATH=""
# for path in "${no_ext_files[@]}"; do
#     printf -v escaped '%q' "$path"
#     DATA_PATH+="$escaped "
# done

node_rank_str=$(printf "%04d" $RANK)
export ASCEND_PROCESS_LOG_PATH=$log_dir/plogs/node${node_rank_str}_$XDL_IP
export TTP_LOG_PATH=$log_dir/ttplogs/node${node_rank_str}_${XDL_IP}
export TRAIN_LOG_PATH=$log_dir/trainlogs/node${node_rank_str}_${XDL_IP}.log
if [[ "${RANK}" -eq 0 ]]; then
    mkdir -p $log_dir/plogs
    mkdir -p $log_dir/ttplogs
    mkdir -p $log_dir/trainlogs
    printenv > $log_dir/env_vars
fi

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

# #环境变量#粗粒度绑核
# export CPU_AFFINITY_CONF=1
# #细粒度绑核
# export CPU_AFFINITY_CONF=2
# #增加二级流水
# export TASK_QUEUE_ENABLE=1

# NPUS_PER_NODE=8
# MASTER_ADDR=localhost
# MASTER_PORT=6000
# NNODES=1
# NODE_RANK=0
# WORLD_SIZE=$(($NPUS_PER_NODE*$NNODES))

# CKPT_SAVE_DIR="your model save ckpt path"
# DATA_PATH="your data path"
# TOKENIZER_PATH="your tokenizer path"
# CKPT_LOAD_DIR="your model ckpt path"
rm -rf /root/.cache/torch_extensions/py310_cpu/
python -c "import mindspeed; from mindspeed.op_builder import GMMOpBuilder; GMMOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import GMMV2OpBuilder; GMMV2OpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MatmulAddOpBuilder; MatmulAddOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MoeTokenPermuteOpBuilder; MoeTokenPermuteOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import MoeTokenUnpermuteOpBuilder; MoeTokenUnpermuteOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import RotaryPositionEmbeddingOpBuilder; RotaryPositionEmbeddingOpBuilder().load()" &
python -c "import mindspeed; from mindspeed.op_builder import GroupMatmulAddOpBuilder; GroupMatmulAddOpBuilder().load()"


TP=2
PP=4
EP=32
CP=1
CP_TYPE='ulysses_cp_algo'
NUM_LAYERS=32
SEQ_LEN=4096
MBS=1
GBS=98304
TRAIN_ITERS=500
SAVE_ITERS=300

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
    --mla-fa-without-pad \
"
    # --moe-alltoall-overlap-comm \
        # --moe-router-num-groups 8 \
    # --moe-router-group-topk 4 \
MOE_ARGS="
    --moe-grouped-gemm \
    --moe-token-dispatcher-type alltoall \
    --use-fused-moe-token-permute-and-unpermute \
    --moe-permutation-async-comm \
    --first-k-dense-replace 3 \
    --moe-layer-freq 1 \
    --n-shared-experts 1 \
    --num-experts 128 \
    --moe-router-topk 2 \
    --moe-ffn-hidden-size 2048 \
    --moe-router-load-balancing-type aux_loss \
    --moe-router-num-groups 8 \
    --moe-router-group-topk 2 \
    --moe-router-topk-scaling-factor 2.827 \
    --moe-aux-loss-coeff 0.001 \
    --seq-aux \
    --norm-topk-prob \
    --moe-router-score-function sigmoid \
    --moe-router-enable-expert-bias \
    --moe-router-dtype fp32 \
    --moe-shared-expert-overlap
"
BALANCE_ARGS="
    --balanced-moe-experts \

"

SWA_ARGS="
    --swa-windows 128 \
    --full-attention-layers ${MANUAL_FULL_LAYERS} \
    --mla-fa-divide-qk \
"

GQA_ARGS="
    --kv-channels 64 \
    --qk-layernorm \
    --num-attention-heads 128 \
    --num-query-groups 4 \
    --group-query-attention \
"


DUALPIPE_ARGS="
    --moe-fb-overlap \
    --schedules-method dualpipev \
"
    # --dualpipev-dw-detach \

ROPE_ARGS="
    --beta-fast 1 \
    --beta-slow 1 \
    --rope-scaling-factor 32 \
    --rope-scaling-mscale 1.0 \
    --rope-scaling-mscale-all-dim  1.0 \
    --rope-scaling-original-max-position-embeddings 4096 \
    --rope-scaling-type yarn
"
#   --num-layer-list 8,8,8,8,8,8,8,5  \
# --reuse-fp32-param \
    # --swap-optimizer \
        # --fix-router \
            # --swap-optimizer \
    # --recompute-granularity full \
    # --recompute-method block \
    # --recompute-num-layers 3 \
GPT_ARGS="
    --spec mindspeed_llm.tasks.models.spec.qwen3_spec layer_spec \
    --gemm-gradient-accumulation-fusion \
    --swap-optimizer \

    --recompute-granularity full \
    --recompute-method block \
    --recompute-num-layers 4 \
    --noop-layers 7,15,23,31 \
    --expert-tensor-parallel-size 1 \
    --no-shared-storage \
    --use-distributed-optimizer \
    --use-flash-attn \
    --use-mcore-models \
    --tensor-model-parallel-size ${TP} \
    --pipeline-model-parallel-size ${PP} \

    --expert-model-parallel-size ${EP} \
    --sequence-parallel \
    --context-parallel-size ${CP} \
    --context-parallel-algo  ${CP_TYPE} \
    --num-layers ${NUM_LAYERS} \
    --hidden-size 4096 \
    --ffn-hidden-size 11264 \
    --tokenizer-type PretrainedFromHF  \
    --tokenizer-name-or-path ${TOKENIZER_PATH} \
    --seq-length ${SEQ_LEN} \
    --max-position-embeddings 131072 \
    --micro-batch-size ${MBS} \
    --global-batch-size ${GBS} \
    --make-vocab-size-divisible-by 1 \
    --lr 1.0e-5 \
    --train-iters $TRAIN_ITERS \
    --lr-decay-style cosine \
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
    --min-lr 1.0e-7 \
    --weight-decay 1e-2 \
    --lr-warmup-iters 0 \
    --clip-grad 1.0 \
    --adam-beta1 0.9 \
    --adam-beta2 0.95 \
    --initial-loss-scale 65536 \
    --vocab-size 163840 \
    --padded-vocab-size 163840 \
    --rotary-base 50000 \
    --norm-epsilon 1e-6 \
    --no-load-optim \
    --no-load-rng \
    --seed 2233 \
    --bf16 \
    --distributed-timeout-minutes 120 \
"

DATA_ARGS="
    --data-path $DATA_PREFIXES \
    --split 100,0,0 \
"

OUTPUT_ARGS="
    --log-interval 1 \
    --log-throughput \
    --save-interval $SAVE_ITERS \
    --eval-interval $TRAIN_ITERS \
    --eval-iters 0 \
"

PROFILING_ARGS="
    --profile \
    --profile-step-start  60  \
    --profile-step-end 61 \
    --profile-ranks 0 \
    --profile-level level1 \
    --profile-with-cpu \
    --profile-with-memory \
    --profile-record-shapes \
    --profile-save-path $log_dir/profiling \
"

unset HIGH_AVAILABILITY

torchrun $DISTRIBUTED_ARGS pretrain_gpt.py \
    $GPT_ARGS \
    $GQA_ARGS \
    $DUALPIPE_ARGS \
    $ROPE_ARGS \
    $MOE_ARGS \
    $OUTPUT_ARGS \
    $DATA_ARGS \
    $PROFILING_ARGS \
    --save ${CKPT_SAVE_DIR} \
    --distributed-backend nccl \
    2>&1 | tee ${TRAIN_LOG_PATH}
