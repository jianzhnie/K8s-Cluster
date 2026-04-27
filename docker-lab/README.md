# docker-lab

Docker 实践工具箱 — 镜像构建、容器部署、集群管理、运维文档，包罗万象。

## 目录结构

```
docker-lab/
├── build_image.sh            # 构建 Docker 镜像（vLLM-Ascend 环境）
├── export_image.sh           # 导出镜像为 tar.gz
├── sync_dist.sh              # 同步分发文件到远程节点
├── dockerfile/
│   └── Dockerfile.vllm-ascend   # vLLM + Ascend NPU 镜像定义
├── cluster/                  # 集群部署工具集
│   ├── install.sh            # Docker 离线安装
│   ├── load_image.sh         # 镜像导入（自动清理旧镜像）
│   ├── run_container.sh      # 容器启动（单卡/多卡/多机/Ray）
│   ├── ray_cluster.sh        # Ray 集群一键管理
│   ├── uninstall.sh          # 卸载清理
│   └── README.md             # 集群部署详细指南
└── docs/
    └── tutorial.md           # Docker 常用命令参考手册
```

## 快速开始

### 构建镜像

```bash
bash build_image.sh
```

### 运行容器

```bash
bash run_container.sh 0                # 使用物理卡 0
bash run_container.sh 0,1              # 使用物理卡 0 + 1
bash run_container.sh --multi-node     # 多机模式（全部芯片）
```

### 导出 / 导入

```bash
# 导出
bash export_image.sh
# 目标机器导入
docker load < ascend910c-cann8.5.1-torch2.9.0-vllm0.18.0.tar.gz
```

### 同步到远程节点

```bash
bash sync_dist.sh                       # 同步分发文件
bash sync_dist.sh --with-npuslim        # 同时同步 NPUSlim 源码
bash sync_dist.sh --with-large          # 包含大文件（镜像 tarball）
```

## 子项目文档

| 目录 | 说明 | 文档 |
|------|------|------|
| `cluster/` | 集群部署、多机分布式推理、Ray 集群管理 | [cluster/README.md](cluster/README.md) |
| `docs/` | Docker 命令速查手册（从入门到进阶） | [docs/tutorial.md](docs/tutorial.md) |
