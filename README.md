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

## 4. K8s YAML 配置详解
**文件：** [tutorial/K8s-YAML配置详解.md](tutorial/K8s-YAML配置详解.md)
- 详细解释 K8s 中常用的 YAML 配置文件。
- 包括 Deployment, Service, Volume, ConfigMap, Secret 等核心组件的配置。
- 适合进阶开发者或系统管理员学习 K8s 配置。

## 5. K8s 集群扩容与维护
**文件：** [tutorial/K8s集群扩容.md](tutorial/K8s集群扩容.md)
- 详细讲解 K8s 集群节点扩容操作。
- 包括添加新节点、配置网络路由、挂载目录等步骤。
- 适合系统管理员或运维人员进行集群维护。


## 其他帮助文档
**文件：** [helper.md](helper.md)
- 包含 rsync 等常用工具的使用说明。
- 适合需要频繁操作文件传输的开发者。
