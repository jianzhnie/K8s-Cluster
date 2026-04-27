#!/bin/bash
# Build vLLM-Ascend Docker Image
# Usage: bash build_image.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build_context"

# 版本信息
CANN_VER="8.5.1"
TORCH_VER="2.9.0"
VLLM_VER="0.18.0"
CHIP_NAME="910c"

IMAGE_NAME="ascend${CHIP_NAME}-cann${CANN_VER}-torch${TORCH_VER}-vllm${VLLM_VER}"
IMAGE_NAME=$(echo "${IMAGE_NAME}" | tr '[:upper:]' '[:lower:]')

echo "========================================"
echo "Building Docker Image"
echo "Image: ${IMAGE_NAME}"
echo "========================================"

# Remove old image with the same name
if docker image inspect "${IMAGE_NAME}" &>/dev/null; then
    echo "Removing old image: ${IMAGE_NAME}"
    docker rmi "${IMAGE_NAME}" >/dev/null
fi

# Clean build context
if [ -d "${BUILD_DIR}" ]; then
    echo "Cleaning old build context..."
    chmod -R u+w "${BUILD_DIR}" 2>/dev/null || true
    rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}/ascend"
mkdir -p "${BUILD_DIR}/conda"

# ============ Step 1: Copy CANN ============
echo "[1/4] Copying CANN toolkit (preserving symlinks)..."
if [ -d "/home/lichc/Ascend/cann-8.5.1" ]; then
    tar -C /home/lichc/Ascend -cf - cann-8.5.1 | tar -C "${BUILD_DIR}/ascend" -xf -
    ln -sf cann-8.5.1 "${BUILD_DIR}/ascend/cann"
else
    echo "ERROR: CANN not found at /home/lichc/Ascend/cann-8.5.1"
    exit 1
fi

# ============ Step 2: Copy NNAL ============
echo "[2/4] Copying NNAL (ATB, preserving symlinks)..."
if [ -d "/home/lichc/Ascend/nnal" ]; then
    tar -C /home/lichc/Ascend -cf - nnal | tar -C "${BUILD_DIR}/ascend" -xf -
else
    echo "ERROR: NNAL not found at /home/lichc/Ascend/nnal"
    exit 1
fi

# ============ Step 3: Package Conda Environment ============
echo "[3/4] Packaging conda environment 'vllm'..."

if ! command -v conda-pack &> /dev/null; then
    echo "Installing conda-pack..."
    pip install -q conda-pack
fi

VLLM_ENV_PATH="/home/lichc/miniforge3/envs/vllm"
if [ -d "${VLLM_ENV_PATH}" ]; then
    conda-pack -n vllm -o "${BUILD_DIR}/conda/conda_env.tar.gz" \
        --ignore-missing-files \
        --force -q
else
    echo "ERROR: vllm conda environment not found at ${VLLM_ENV_PATH}"
    exit 1
fi

# ============ Step 4: Build Image ============
echo "[4/4] Preparing and building Docker image..."

cp "${SCRIPT_DIR}/Dockerfile.vllm-ascend" "${BUILD_DIR}/Dockerfile"
cp "${SCRIPT_DIR}/entrypoint.sh" "${BUILD_DIR}/entrypoint.sh"
cp "${SCRIPT_DIR}/ascend_env.sh" "${BUILD_DIR}/ascend_env.sh"

echo ""
echo "Build context size:"
du -sh "${BUILD_DIR}"/*

cd "${BUILD_DIR}"

HOST_IP="172.17.0.1"
PROXY_PORT=7897
PROXY_URL="http://${HOST_IP}:${PROXY_PORT}"

echo "Using proxy: ${PROXY_URL}"
echo "Host platform: $(uname -m)"

docker build \
    --platform linux/arm64 \
    --build-arg http_proxy="${PROXY_URL}" \
    --build-arg https_proxy="${PROXY_URL}" \
    --build-arg no_proxy=localhost,127.0.0.1,.huawei.com \
    -t "${IMAGE_NAME}" .

echo ""
echo "========================================"
echo "Build Complete!"
echo "Image: ${IMAGE_NAME}"
echo "========================================"
echo ""
echo "Next steps:"
echo "  bash run_container.sh 0                # pure vllm"
echo "  bash run_container.sh 0 --npuslim      # with npuslim (dev)"
echo "  bash run_container.sh --multi-node     # multi-node"
