#!/bin/bash
# Load (or reload) Docker image from tarball
# Usage: bash load_docker_image.sh [--tarball <path>]
#   Default tarball: the only .tar.gz in this directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 镜像名称和标签
IMAGE_REPO="swr.cn-south-1.myhuaweicloud.com/ascendhub/mindspeed-llm"
IMAGE_TAG="26.0.0-a3-openeuler24.03-py3.11-aarch64"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"
TARBALL="/home/jianzhnie/llmtuner/hfhub/docker/image/mindspeed-llm-26.0.0-a3-arm.tar.gz"

# IMAGE_REPO="cis-pengcheng.cmecloud.cn/ascendhub/mindspeed-llm"
# IMAGE_TAG="openeuler22.03-mindspeed-llm-2.3.0-a3-arm"
# IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"
# TARBALL=""

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --tarball) TARBALL="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Auto-detect tarball
if [ -z "$TARBALL" ]; then
    TARBALLS=( "$SCRIPT_DIR"/*.tar.gz )
    if [ ${#TARBALLS[@]} -gt 1 ]; then
        echo "WARNING: Multiple .tar.gz files found, using: ${TARBALLS[0]}"
    fi
    TARBALL="${TARBALLS[0]}"
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "ERROR: No .tar.gz found in ${SCRIPT_DIR}"
    echo "Usage: bash load_docker_image.sh [--tarball <path>]"
    exit 1
fi

# Check Docker availability
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or not accessible"
    exit 1
fi

echo "========================================"
echo "Load Docker Image"
echo "========================================"
echo "Image:   ${IMAGE_NAME}"
echo "Tarball: ${TARBALL}"
echo ""

# Load image first, then remove the old one to avoid data loss on failure
OLD_ID=$(docker image inspect "${IMAGE_NAME}" --format '{{.Id}}' 2>/dev/null || true)

echo "Loading image (this may take a while)..."
docker load -i "${TARBALL}"

# Remove old image if it was replaced (different ID)
if [ -n "$OLD_ID" ]; then
    NEW_ID=$(docker image inspect "${IMAGE_NAME}" --format '{{.Id}}' 2>/dev/null || true)
    if [ -n "$NEW_ID" ] && [ "$OLD_ID" != "$NEW_ID" ]; then
        echo "Cleaning up old image (${OLD_ID:0:12})..."
        docker rmi "${OLD_ID}" >/dev/null 2>&1 || true
    fi
fi

echo ""
echo "========================================"
echo "Done."
echo "========================================"
