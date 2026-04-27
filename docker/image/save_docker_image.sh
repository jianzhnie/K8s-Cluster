#!/bin/bash
set -e

# 镜像名称和标签
IMAGE_REPO="cis-pengcheng.cmecloud.cn/ascendhub/mindspeed-llm"
IMAGE_TAG="openeuler22.03-mindspeed-llm-2.3.0-a3-arm"
FULL_IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

# 输出文件名
OUTPUT_FILE="mindspeed-llm-2.3.0-a3-arm.tar"

echo "正在保存镜像: ${FULL_IMAGE_NAME}"
echo "保存路径: $(pwd)/${OUTPUT_FILE}"
echo "这可能需要几分钟时间（镜像大小约 15.8GB）..."

if docker save -o "${OUTPUT_FILE}" "${FULL_IMAGE_NAME}"; then
    echo "✅ 镜像保存成功！"
    ls -lh "${OUTPUT_FILE}"
else
    echo "❌ 镜像保存失败。请检查 Docker 是否正在运行。"
    exit 1
fi
