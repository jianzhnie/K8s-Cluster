#!/bin/bash
set -euo pipefail

# 镜像名称和标签
IMAGE_REPO="cis-pengcheng.cmecloud.cn/ascendhub/mindspeed-llm"
IMAGE_TAG="openeuler22.03-mindspeed-llm-2.3.0-a3-arm"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

# 输出文件名 (compressed)
OUTPUT_FILE="mindspeed-llm-2.3.0-a3-arm.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="${SCRIPT_DIR}/${OUTPUT_FILE}"

# Cleanup on interrupt
cleanup() {
    echo ""
    echo "Interrupted, removing partial file..."
    rm -f "${OUTPUT_PATH}"
    exit 130
}
trap cleanup INT TERM

# Check Docker availability
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or not accessible"
    exit 1
fi

# Check if image exists
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "ERROR: Image not found: ${IMAGE_NAME}"
    exit 1
fi

echo "Saving image: ${IMAGE_NAME}"
echo "Output path:  ${OUTPUT_PATH}"
echo "This may take several minutes..."
echo ""

echo "========================================"
if docker save "${IMAGE_NAME}" | gzip > "${OUTPUT_PATH}"; then
    echo "Image saved successfully!"
else
    echo "ERROR: Failed to save image."
    rm -f "${OUTPUT_PATH}"
    exit 1
fi
echo "========================================"
echo ""
echo "File: ${OUTPUT_PATH}"
echo "Size: $(du -sh "${OUTPUT_PATH}" | cut -f1)"
echo ""
echo "Transfer and import on target:"
echo "  gunzip -c ${OUTPUT_FILE} | docker load"
