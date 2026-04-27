#!/bin/bash
# Load (or reload) Docker image from tarball
# Usage: bash load_image.sh [--tarball <path>]
#   Default tarball: the only .tar.gz in this directory matching the image name

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Version info (keep in sync with run_container.sh)
CANN_VER="8.5.1"
TORCH_VER="2.9.0"
VLLM_VER="0.18.0"
CHIP_NAME="910c"

IMAGE_NAME="ascend${CHIP_NAME}-cann${CANN_VER}-torch${TORCH_VER}-vllm${VLLM_VER}"
IMAGE_NAME=$(echo "${IMAGE_NAME}" | tr '[:upper:]' '[:lower:]')

TARBALL=""

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --tarball) TARBALL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Auto-detect tarball
if [ -z "$TARBALL" ]; then
    TARBALL=$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.tar.gz' | head -1)
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "ERROR: No .tar.gz found in ${SCRIPT_DIR}"
    echo "Usage: bash load_image.sh [--tarball <path>]"
    exit 1
fi

echo "========================================"
echo "Load Docker Image"
echo "========================================"
echo "Image:   ${IMAGE_NAME}"
echo "Tarball: ${TARBALL}"
echo ""

# Remove old image if exists
OLD_ID=$(docker image inspect "${IMAGE_NAME}" --format '{{.Id}}' 2>/dev/null || true)
if [ -n "$OLD_ID" ]; then
    echo "Removing old image ${IMAGE_NAME}..."
    docker rmi "${IMAGE_NAME}" >/dev/null
    echo ""
fi

echo "Loading image (this may take a while)..."
docker load -i "${TARBALL}"

echo ""
echo "========================================"
echo "Done."
echo "========================================"
