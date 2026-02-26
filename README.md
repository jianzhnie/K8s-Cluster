# K8s Cluster 学习与实践指南

本项目包含 Kubernetes 集群学习资料及 Huawei Ascend 910B 训练实践指南。主要包含以下三个核心文档：

## 1. Kubernetes 初学者指南
**文件：** [tutorial/kubernetes_beginner_guide.md](tutorial/kubernetes_beginner_guide.md)
- 面向零基础初学者。
- 涵盖 K8s 基础架构、核心概念（Namespace, Pod, Deployment, Service）及入门操作。
- 适合刚接触 K8s 的开发者快速上手。

## 2. K8s 集群常用命令速查手册
**文件：** [tutorial/K8s集群常用命令.md](tutorial/K8s集群常用命令.md)
- 汇集日常运维、开发调试及故障处理的高频命令。
- 包含集群管理、Pod 操作、网络调试及 AscendJob 专用命令。
- 适合作为日常工作的案头速查工具。

## 3. Huawei Ascend 910B PyTorch 训练实践
**文件：** [tutorial/K8s-Train.md](tutorial/K8s-Train.md)
- 针对 Ascend 910B 芯片在 K8s 环境下的深度学习训练指南。
- 详细讲解单机多卡与多机多卡训练配置（AscendJob）。
- 包含故障自愈（Volcano + MindX DL）及核心参数解析。
