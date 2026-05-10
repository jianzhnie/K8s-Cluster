# Ascend LLM Ops

Docker / Kubernetes / Ascend NPU 大模型训练相关的文档、脚本和配置集合。

## 目录结构

```
├── docker/             Docker 镜像构建、安装与容器管理
│   ├── dockerfile/         Dockerfile（vLLM-Ascend 等）
│   ├── image/              镜像构建、导出、加载脚本
│   ├── install/            Docker 离线安装与卸载
│   └── start_container/    NPU 容器启动脚本
├── docs/               文档
│   └── tutorials/          K8s 入门指南与命令速查
├── k8s/                Kubernetes 配置与脚本
│   ├── configs/            AscendJob YAML（DeepSeek / LLaMA / Qwen / Kimi2）
│   └── k8s_scripts/        训练启动脚本
├── scripts/            训练、评估与推理脚本
│   ├── launch/             单节点 / 多节点训练启动器
│   ├── evaluate/           模型评估（MMLU / GSM8K 等）
│   └── generate/           文本生成推理
└── tools/              集群运维工具
    ├── find-free-node.sh     查找空闲 NPU 节点
    ├── hf_download.sh        HuggingFace 模型下载
    └── ...                   节点管理、进程清理、文件挂载等
```

## 快速导航

### 文档

| 场景 | 链接 |
|------|------|
| Docker 命令参考 | [docs/docker-tutorial.md](docs/docker-tutorial.md) |
| K8s 基础入门 | [docs/tutorials/k8s-beginner-guide.md](docs/tutorials/k8s-beginner-guide.md) |
| K8s 命令速查 | [docs/tutorials/k8s-commands-cheatsheet.md](docs/tutorials/k8s-commands-cheatsheet.md) |
| K8s + Ascend 训练全指南 | [docs/tutorials/k8s-cluster-guide.md](docs/tutorials/k8s-cluster-guide.md) |
| 集群节点扩缩容 | [docs/tutorials/k8s-cluster-scaling.md](docs/tutorials/k8s-cluster-scaling.md) |
| Ascend 环境变量参考 | [docs/ascend-env-reference.md](docs/ascend-env-reference.md) |

## License

[Apache 2.0](LICENSE)
