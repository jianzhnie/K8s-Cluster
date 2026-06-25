#!/bin/bash
# ============================================================
# Build script for torchtitan-npu Docker image
# ============================================================
# Must be run from the parent directory that contains:
#   torchtitan-npu/      (local source, master branch)
#   torchtitan/          (upstream, pinned commit ac13e536)
#   ascend-llm-ops/      (this repo)
#
# Usage:
#   cd /home/jianzhnie/llmtuner/llm
#   bash ascend-llm-ops/docker/dockerfile/build_torchtitan_npu.sh [TAG]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONTEXT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

IMAGE_NAME="torchtitan-npu"
IMAGE_TAG="${1:-cann9.0.0-torch2.12.0}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
DOCKERFILE="${SCRIPT_DIR}/Dockerfile.torchtitan-npu"

echo "============================================="
echo " Building torchtitan-npu Docker image"
echo "============================================="
echo " Image      : ${FULL_IMAGE}"
echo " Dockerfile : ${DOCKERFILE}"
echo " Context    : ${BUILD_CONTEXT}"
echo "============================================="

# --- Sanity check: torchtitan-npu ---
if [ ! -f "${BUILD_CONTEXT}/torchtitan-npu/pyproject.toml" ]; then
    echo "[ERROR] torchtitan-npu source not found at ${BUILD_CONTEXT}/torchtitan-npu"
    echo "        Ensure the local clone exists and pyproject.toml is present."
    exit 1
fi
echo "[INFO] torchtitan-npu : OK"

# --- Sanity check: torchtitan (upstream, pinned commit) ---
if [ ! -f "${BUILD_CONTEXT}/torchtitan/pyproject.toml" ]; then
    echo "[ERROR] torchtitan source not found at ${BUILD_CONTEXT}/torchtitan"
    echo "        Clone and pin the commit with:"
    echo "          cd ${BUILD_CONTEXT}"
    echo "          git clone https://github.com/pytorch/torchtitan.git torchtitan"
    echo "          git -C torchtitan checkout ac13e536c84e7f6647b14fa9375c3c8a8a2b8578"
    exit 1
fi
TITAN_COMMIT="$(git -C "${BUILD_CONTEXT}/torchtitan" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo "[INFO] torchtitan     : OK (commit: ${TITAN_COMMIT})"

echo "[INFO] Starting docker build..."
echo ""

docker build \
    --file "${DOCKERFILE}" \
    --tag "${FULL_IMAGE}" \
    --progress=plain \
    "${BUILD_CONTEXT}"

echo ""
echo "============================================="
echo " Build complete: ${FULL_IMAGE}"
echo "============================================="
echo ""
echo "Verify the environment:"
echo "  docker run --rm ${FULL_IMAGE} python /workspace/verify_torchtitan.py"
echo ""
echo "Interactive shell:"
echo "  docker run --rm -it ${FULL_IMAGE}"
