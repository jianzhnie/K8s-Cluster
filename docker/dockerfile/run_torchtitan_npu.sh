#!/bin/bash
# ============================================================
# Run torchtitan-npu training container
# ============================================================
# Usage:
#   bash run_torchtitan_npu.sh [--cards 0,1,2,...] [--name NAME] [CMD...]
#
# Examples:
#   # Interactive shell with all 8 NPUs
#   bash run_torchtitan_npu.sh
#
#   # Run SFT debug config directly
#   bash run_torchtitan_npu.sh -- bash -c \
#     "cd /workspace/torchtitan-npu && \
#      NGPU=8 MODULE=torchtitan_npu.models.qwen3 CONFIG=sft_qwen3_0_6b_debug \
#      bash scripts/run_train.sh"
# ============================================================

set -euo pipefail

IMAGE="torchtitan-npu:cann9.0.0-torch2.12.0"
CONTAINER_NAME="torchtitan-npu-sft"
CARDS="0,1,2,3,4,5,6,7"   # NPU card IDs to expose (comma-separated)

# ---- host paths (adjust if different) ----
HOST_SOURCE="/home/jianzhnie/llmtuner/llm/torchtitan-npu"
HOST_HF_MODELS="/home/jianzhnie/llmtuner/hfhub/models/Qwen"
HOST_HF_DATASETS="/home/jianzhnie/llmtuner/hfhub/datasets"
HOST_HF_CACHE="/root/.cache"
HOST_CHECKPOINTS="/home/jianzhnie/llmtuner/llm/torchtitan-npu/checkpoints"

# ---- container paths ----
CONT_SOURCE="/workspace/torchtitan-npu"
CONT_HF_MODELS="/workspace/hf"
CONT_DATASETS="/workspace/datasets"
CONT_CHECKPOINTS="/workspace/checkpoints"

mkdir -p "${HOST_CHECKPOINTS}"

# ---- parse args ----
CMD=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) CONTAINER_NAME="$2"; shift 2 ;;
        --name=*) CONTAINER_NAME="${1#--name=}"; shift ;;
        --cards) CARDS="$2"; shift 2 ;;
        --cards=*) CARDS="${1#--cards=}"; shift ;;
        --) shift; CMD=("$@"); break ;;
        *) CMD+=("$1"); shift ;;
    esac
done

# Default to interactive bash
if [[ ${#CMD[@]} -eq 0 ]]; then
    CMD=(/bin/bash -l)
fi

# Build --device flags from CARDS
DEVICE_FLAGS=()
IFS=',' read -ra _card_ids <<< "$CARDS"
for _cid in "${_card_ids[@]}"; do
    _cid="${_cid// /}"   # trim any whitespace
    DEVICE_FLAGS+=(--device="/dev/davinci${_cid}")
done

echo "============================================="
echo " Starting torchtitan-npu container"
echo "============================================="
echo " Image     : ${IMAGE}"
echo " Container : ${CONTAINER_NAME}"
echo " Cards     : ${CARDS}"
echo " Source    : ${HOST_SOURCE} → ${CONT_SOURCE}"
echo " Models    : ${HOST_HF_MODELS} → ${CONT_HF_MODELS}"
echo " Datasets  : ${HOST_HF_DATASETS} → ${CONT_DATASETS}"
echo " Command   : ${CMD[*]}"
echo "============================================="

# Remove existing stopped container with same name (if any).
# WARNING: also stops a running container — do not run if a training job is active.
if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
    echo "[WARN] Removing existing container '${CONTAINER_NAME}'..."
    docker rm -f "${CONTAINER_NAME}"
fi

docker run \
    --name "${CONTAINER_NAME}" \
    --rm \
    -it \
    --ipc=host \
    --net=host \
    --privileged \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    `# NPU devices (cards: ${CARDS})` \
    "${DEVICE_FLAGS[@]}" \
    --device=/dev/davinci_manager \
    --device=/dev/devmm_svm \
    --device=/dev/hisi_hdc \
    `# Ascend driver` \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/Ascend/add-ons/:/usr/local/Ascend/add-ons/ \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /usr/local/Ascend/driver/lib64/:/usr/local/Ascend/driver/lib64/ \
    -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
    -v /etc/ascend_install.info:/etc/ascend_install.info \
    `# torchtitan-npu source (editable, overrides image install)` \
    -v "${HOST_SOURCE}:${CONT_SOURCE}" \
    `# Qwen model weights (entire Qwen dir → /workspace/hf)` \
    -v "${HOST_HF_MODELS}:${CONT_HF_MODELS}:ro" \
    `# HuggingFace datasets` \
    -v "${HOST_HF_DATASETS}:${CONT_DATASETS}:ro" \
    `# Checkpoint output (write)` \
    -v "${HOST_CHECKPOINTS}:${CONT_CHECKPOINTS}" \
    `# HF hub cache (avoid re-downloads)` \
    -v "${HOST_HF_CACHE}:/root/.cache" \
    `# HF offline mode: use only cached/mounted data` \
    -e HF_DATASETS_OFFLINE=1 \
    -e TRANSFORMERS_OFFLINE=1 \
    -e HF_HUB_OFFLINE=1 \
    `# HCCL port range — avoids conflict with other containers on --net=host` \
    -e HCCL_NPU_SOCKET_PORT_RANGE=30000,1024 \
    -w "${CONT_SOURCE}" \
    "${IMAGE}" \
    "${CMD[@]}"
