# 修改 ascend-toolkit 路径
source /usr/local/Ascend/ascend-toolkit/set_env.sh
export CUDA_DEVICE_MAX_CONNECTIONS=1

# 请根据实际并行策略修改参数
# 如果 PP > 1 且 layer 数不能整除 PP，需要指定 --num-layer-list
python examples/mcore/kimi2/convert_ckpt_kimi2_mcore2hf.py \
    --source-tensor-parallel-size 1 \
    --source-pipeline-parallel-size 1 \
    --source-expert-parallel-size 1 \
    --load-dir ./model_weights/kimi2-mcore \
    --save-dir ./model_from_hf/kimi2-hf \
    --num-layers 61 \
    --first-k-dense-replace 1 \
    # --moe-grouped-gemm \
    # --num-layer-list 8,8,8,8,8,8,8,5  # 示例: PP=8, total=61
