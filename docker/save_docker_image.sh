#!/bin/bash
# ============================================================
# save_docker_image.sh — General-purpose Docker image packer
# ============================================================
# Saves a Docker image to a compressed .tar.gz archive using
# pigz (parallel gzip) when available, falling back to gzip.
#
# Usage:
#   bash save_docker_image.sh <IMAGE:TAG> [OUTPUT_DIR]
#
# Examples:
#   bash save_docker_image.sh torchtitan-npu:cann9.0.0-torch2.12.0
#   bash save_docker_image.sh torchtitan-npu:cann9.0.0-torch2.12.0 /data/images
#   bash save_docker_image.sh vllm-ascend:v0.20.2rc1-a3 /home/user/docker/image
#
# Output filename convention:
#   <image-name>.<tag>.tar.gz   (colons and slashes replaced with dots/dashes)
#
# Features:
#   - pigz multi-thread compression (falls back to gzip -1)
#   - Post-save integrity check (pigz -t / gzip -t)
#   - Image existence check before starting
#   - Prints compressed/uncompressed sizes and compression ratio
# ============================================================

set -euo pipefail

# ---- colours ------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BOLD}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- usage --------------------------------------------------
usage() {
    sed -n '3,20p' "$0" | sed 's/^# \?//'
    exit 1
}

[[ $# -lt 1 ]] && usage

IMAGE_REF="$1"
OUTPUT_DIR="${2:-$(pwd)}"

# ---- validate image exists ----------------------------------
if ! docker image inspect "${IMAGE_REF}" &>/dev/null; then
    error "Image '${IMAGE_REF}' not found locally."
    echo "  Available images:"
    docker images --format "    {{.Repository}}:{{.Tag}}\t{{.Size}}" | head -20
    exit 1
fi

# ---- derive output filename ---------------------------------
# torchtitan-npu:cann9.0.0-torch2.12.0 -> torchtitan-npu.cann9.0.0-torch2.12.0.tar.gz
# quay.io/ascend/vllm-ascend:v0.20.2   -> ascend.vllm-ascend.v0.20.2.tar.gz
SAFE_NAME="$(echo "${IMAGE_REF}" | sed 's|.*/||; s|:|\.|g')"
OUTPUT_FILE="${OUTPUT_DIR}/${SAFE_NAME}.tar.gz"

mkdir -p "${OUTPUT_DIR}"

# ---- detect compressor --------------------------------------
THREADS="$(nproc 2>/dev/null || echo 4)"
if command -v pigz &>/dev/null; then
    COMPRESSOR="pigz -p ${THREADS}"
    TESTER="pigz -t"
    COMPRESSOR_NAME="pigz (${THREADS} threads)"
else
    warn "pigz not found, falling back to gzip -1 (slower)"
    COMPRESSOR="gzip -1"
    TESTER="gzip -t"
    COMPRESSOR_NAME="gzip -1"
fi

# ---- image metadata -----------------------------------------
IMAGE_ID="$(docker image inspect "${IMAGE_REF}" --format '{{.Id}}' | cut -c8-19)"
IMAGE_SIZE="$(docker image inspect "${IMAGE_REF}" --format '{{.Size}}' | numfmt --to=iec 2>/dev/null || echo 'unknown')"
LAYER_COUNT="$(docker image inspect "${IMAGE_REF}" --format '{{len .RootFS.Layers}}')"

echo ""
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD} Docker Image Save${NC}"
echo -e "${BOLD}=============================================${NC}"
info "Image      : ${IMAGE_REF}"
info "Image ID   : ${IMAGE_ID}"
info "Image size : ${IMAGE_SIZE} (${LAYER_COUNT} layers)"
info "Output     : ${OUTPUT_FILE}"
info "Compressor : ${COMPRESSOR_NAME}"
echo -e "${BOLD}=============================================${NC}"
echo ""

# ---- check existing file ------------------------------------
if [[ -f "${OUTPUT_FILE}" ]]; then
    warn "Output file already exists: ${OUTPUT_FILE}"
    warn "It will be overwritten."
    echo ""
fi

# ---- save + compress ----------------------------------------
START_TS="$(date +%s)"
info "Starting docker save | ${COMPRESSOR_NAME} ..."
echo ""

docker save "${IMAGE_REF}" | ${COMPRESSOR} > "${OUTPUT_FILE}"

END_TS="$(date +%s)"
ELAPSED=$(( END_TS - START_TS ))

# ---- sizes & ratio ------------------------------------------
COMP_BYTES="$(stat -c%s "${OUTPUT_FILE}")"
COMP_HUMAN="$(numfmt --to=iec "${COMP_BYTES}" 2>/dev/null || echo "${COMP_BYTES} bytes")"

# Decompress to count real bytes (fast path: just count, no write)
info "Calculating uncompressed size..."
UNCOMP_BYTES="$(${TESTER%% *} -d -c "${OUTPUT_FILE}" | wc -c)"
UNCOMP_HUMAN="$(numfmt --to=iec "${UNCOMP_BYTES}" 2>/dev/null || echo "${UNCOMP_BYTES} bytes")"

RATIO=$(awk "BEGIN { printf \"%.1f\", (1 - ${COMP_BYTES}/${UNCOMP_BYTES}) * 100 }")

# ---- integrity check ----------------------------------------
echo ""
info "Verifying archive integrity..."
if ${TESTER} "${OUTPUT_FILE}"; then
    ok "Integrity check passed"
else
    error "Integrity check FAILED — archive may be corrupt!"
    exit 1
fi

# ---- summary ------------------------------------------------
echo ""
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}=============================================${NC}"
ok "Image      : ${IMAGE_REF} (id: ${IMAGE_ID})"
ok "Output     : ${OUTPUT_FILE}"
ok "Original   : ${UNCOMP_HUMAN}"
ok "Compressed : ${COMP_HUMAN}  (${RATIO}% reduction)"
ok "Time       : ${ELAPSED}s"
echo -e "${BOLD}=============================================${NC}"
echo ""
echo "Restore with:"
echo "  docker load < ${OUTPUT_FILE}"
echo ""
