# Docker & K8s Playbook

Docker / Kubernetes / Ascend NPU 训练相关的文档、脚本和配置集合。

## 目录结构

```
docker-k8s-playbook/
├── docs/                    # 文档
│   ├── tutorials/           #   K8s 学习教程（入门→进阶）
│   ├── docker-tutorial.md   #   Docker 命令速查
│   ├── ascend-env-reference.md  # Ascend 环境变量参考
│   ├── cloudbrain3-ops.md   #   CloudBrain3 运维手册
│   └── linux-docker-basics.md   # Linux/Docker 基础命令
│
├── docker/                  # Docker 工具
│   ├── dockerfile/          #   Dockerfile 模板
│   ├── install.sh           #   Docker 安装（离线）
│   ├── uninstall.sh         #   Docker 卸载
│   ├── run_container.sh     #   启动容器（支持单卡/多卡/多节点）
│   ├── build_image.sh       #   构建镜像（vLLM-Ascend）
│   ├── export_image.sh      #   导出镜像为 tar.gz
│   ├── load_image.sh        #   从 tar.gz 加载镜像
│   ├── save_docker_image.sh #   保存指定镜像
│   ├── ray_cluster.sh       #   Ray 集群管理
│   └── sync_dist.sh         #   分发文件到远程节点
│
├── k8s/                     # K8s 集群管理
│   ├── configs/             #   K8s Job YAML 配置
│   │   ├── kimi2/           #     Kimi-K2 各规模配置
│   │   ├── llama/           #     LLaMA-3.1 各规模配置
│   │   ├── deepseek/        #     DeepSeek-V3 各规模配置
│   │   └── qwen/            #     Qwen3 配置
│   ├── env/                 #   环境配置脚本
│   │   ├── k8s_common_env.sh    # K8s 训练环境
│   │   └── ascend_env.sh        # Ascend Docker 环境
│   ├── node-label.sh        #   批量节点标签
│   ├── node-taint.sh        #   节点污点管理
│   ├── node-find-free.sh    #   查找空闲节点
│   ├── node-extract-ip.py   #   提取节点 IP/机架信息
│   ├── mount-dpcfs.sh       #   挂载 DTFS 文件系统
│   └── start-label-nodes.sh #   标签节点快捷脚本
│
├── training/                # 模型训练/评估/推理
│   ├── launch/              #   通用启动器
│   │   ├── launch_single_node.sh
│   │   ├── launch_multi_nodes.sh
│   │   └── set_env.sh
│   ├── pretrain/            #   预训练脚本（按模型分类）
│   │   ├── kimi2/
│   │   ├── deepseek/
│   │   ├── llama/
│   │   └── qwen/
│   ├── evaluate/            #   评估脚本
│   │   ├── kimi2/
│   │   └── qwen/
│   └── generate/            #   推理生成
│       └── qwen/
│
└── tools/                   # 通用工具
    ├── hf_download.sh       #   HuggingFace 模型下载
    ├── compare_weights/     #   Safetensors 权重对比
    ├── checkpoint/kimi2/    #   Kimi-K2 Checkpoint 转换（HF ↔ MCore）
    ├── get_file_list.py     #   数据集文件列表生成
    ├── create_symlinks.sh   #   批量创建软链接
    ├── kill_process.sh      #   交互式进程清理
    ├── ssh_utils.sh         #   SSH 远程执行工具函数
    └── ops-reference.sh     #   运维操作参考
```

## 快速导航

| 场景 | 去哪里 |
|------|--------|
| 学习 K8s 基础 | [docs/tutorials/k8s-beginner-guide.md](docs/tutorials/k8s-beginner-guide.md) |
| K8s 命令速查 | [docs/tutorials/k8s-commands-cheatsheet.md](docs/tutorials/k8s-commands-cheatsheet.md) |
| Ascend 训练指南 | [docs/tutorials/k8s-training-on-ascend.md](docs/tutorials/k8s-training-on-ascend.md) |
| 构建部署 Docker 镜像 | [docker/](docker/) |
| 提交 K8s 训练任务 | [k8s/configs/](k8s/configs/) |
| 查找/管理集群节点 | [k8s/](k8s/) |
| 运行模型训练 | [training/](training/) |
| 转换模型权重 | [tools/checkpoint/](tools/checkpoint/kimi2/) |
| 下载 HuggingFace 模型 | [tools/hf_download.sh](tools/hf_download.sh) |
