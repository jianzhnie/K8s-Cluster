# 挂载 dtfs
mkdir -p /llm_workspace_1P 
mount -t dtfs /llm_workspace_1P /llm_workspace_1P

mkdir -p /home/jianzhnie/llmtuner
mount -t dtfs /llmtuner /home/jianzhnie/llmtuner

# 设置 kimi-home
export KIMI_CODE_HOME=/home/jianzhnie/llmtuner/kimi-code

# 同步代码
rsync -avz /Users/robin/work_dir/ascend-llm-ops  C3-Kuang119:/home/jianzhnie/llmtuner

# 配置 ssh 免密
bash  /home/jianzhnie/llmtuner/llm/ascend-llm-ops/tools/setup_ssh_nopass.sh -f nodes.txt -u root -p 'iX5@vSogl9'