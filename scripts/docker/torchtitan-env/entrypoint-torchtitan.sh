#!/bin/bash
# ============================================================
# torchtitan-npu Container Entrypoint
# ============================================================
# Sources CANN/Ascend environment, then executes the command.

echo "========================================="
echo " torchtitan-npu Training Environment"
echo "========================================="
echo " Base: vllm-ascend v0.20.2rc1-a3"
echo " CANN:  9.0.0"
echo " NPU:   ascend910_9391"
echo " Torch: 2.12.0 + torch_npu 2.12.0rc1"
echo " triton-ascend: 3.2.1"
echo "========================================="

# Source CANN environment (same as base image)
if [ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]; then
    source /usr/local/Ascend/ascend-toolkit/set_env.sh
fi

if [ -f /usr/local/Ascend/nnal/atb/set_env.sh ]; then
    source /usr/local/Ascend/nnal/atb/set_env.sh
fi

# Additional torchtitan env setup (supplements Dockerfile ENV)
# TORCHTITAN_HOME, TORCHTITAN_NPU_BACKEND, HCCL_* are already set
# as Dockerfile ENV; re-export only if they may be missing at runtime.
export TORCHTITAN_HOME="${TORCHTITAN_HOME:-/workspace/torchtitan-npu}"
export TORCHTITAN_NPU_BACKEND="${TORCHTITAN_NPU_BACKEND:-hccl}"

# Show NPU info (non-fatal if not available)
npu-smi info 2>/dev/null || echo "[INFO] npu-smi not available (expected if NPU devices not mounted)"

echo ""
echo "[INFO] Environment ready. Starting..."

exec "$@"
