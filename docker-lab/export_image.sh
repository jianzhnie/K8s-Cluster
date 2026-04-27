#!/bin/bash
# Export Docker image to tar.gz
# Usage: bash export_image.sh [OUTPUT_DIR]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 版本信息
CANN_VER="8.5.1"
TORCH_VER="2.9.0"
VLLM_VER="0.18.0"
CHIP_NAME="910c"

IMAGE_NAME="ascend${CHIP_NAME}-cann${CANN_VER}-torch${TORCH_VER}-vllm${VLLM_VER}"
IMAGE_NAME=$(echo "${IMAGE_NAME}" | tr '[:upper:]' '[:lower:]')

OUTPUT_DIR="${1:-$SCRIPT_DIR}/distribution"
ARCHIVE_NAME="${IMAGE_NAME}.tar.gz"
OUTPUT_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"

echo "========================================"
echo "Exporting Docker Image"
echo "========================================"
echo "Image:  ${IMAGE_NAME}"
echo "Output: ${OUTPUT_PATH}"
echo ""

if ! docker image inspect "${IMAGE_NAME}" &>/dev/null; then
    echo "ERROR: Image not found: ${IMAGE_NAME}"
    echo "Please run build_image.sh first."
    exit 1
fi

echo "Exporting (this may take several minutes)..."
docker save "${IMAGE_NAME}" | gzip > "${OUTPUT_PATH}"

echo ""
echo "========================================"
echo "Export Complete!"
echo "========================================"
echo ""
echo "File: ${OUTPUT_PATH}"
echo "Size: $(du -sh "${OUTPUT_PATH}" | cut -f1)"
echo ""
echo "Transfer and import on target:"
echo "  docker load < ${ARCHIVE_NAME}"
