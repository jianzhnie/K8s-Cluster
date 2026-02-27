#!/usr/bin/env bash
set -euo pipefail

home_dir="/home/robin/hfhub"

python compare_safetensors.py \
    --source $home_dir/models/moonshotai/Kimi-K2-Base/model-1-of-61.safetensors \
    --target $home_dir/models/moonshotai/Kimi-K2-Base-mcore-2-hf/model-00001-of-000061.safetensors \
    --tolerance 1e-5 \
    --verbose
