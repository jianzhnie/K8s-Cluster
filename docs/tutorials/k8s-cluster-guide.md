# Kubernetes 集群配置与 Ascend 910B 训练全指南

> **文档版本**: v3.0
> **最后更新**: 2026-03-05
> **适用范围**: Kubernetes v1.25+ / Huawei Ascend 910B
> **目标读者**: 运维工程师、SRE、AI 算法工程师

---

## 目录

1.  [前言](#1-前言)
2.  [第一部分：Kubernetes 核心配置详解](#第一部分kubernetes-核心配置详解)
    *   [2.1 核心工作负载 (Deployment/StatefulSet/DaemonSet)](#21-核心工作负载)
    *   [2.2 网络与服务发现 (Service/Ingress)](#22-网络与服务发现)
    *   [2.3 配置与存储 (ConfigMap/Secret)](#23-配置与存储)
    *   [2.4 高级调度与治理 (HPA/PDB/NetworkPolicy)](#24-高级调度与治理)
3.  [第二部分：Huawei Ascend 910B AI 训练实战](#第二部分huawei-ascend-910b-ai-训练实战)
    *   [3.1 快速开始](#31-快速开始)
    *   [3.2 核心配置解析 (AscendJob)](#32-核心配置解析-ascendjob)
    *   [3.3 存储与挂载详解](#33-存储与挂载详解)
    *   [3.4 多机分布式训练专题](#34-多机分布式训练专题)
    *   [3.5 进阶：超节点亲和性调度](#35-进阶超节点亲和性调度)
    *   [3.6 常见问题与排查](#36-常见问题与排查)
4.  [附录：自动化验证脚本](#4-附录自动化验证脚本)

---

## 1. 前言

本指南旨在提供一份从 **通用 Kubernetes 资源管理** 到 **高性能 AI 训练** 的一站式参考文档。
*   **第一部分**：系统性解析 Kubernetes 核心资源的 YAML 配置，以 Guestbook 微服务为例，涵盖从基础部署到高级治理的全流程。
*   **第二部分**：深度聚焦 Huawei Ascend 910B NPU 的训练场景，基于 `AscendJob` (CRD) 和 Volcano 调度器，详解单机与多机分布式训练的最佳实践。

---

# 第一部分：Kubernetes 核心配置详解

## 2.1 核心工作负载

### Deployment - 无状态应用
用于管理无状态应用（如 Web Server）。它处理 Pod 的副本管理、滚动更新和回滚。

**核心字段解析**:
| 字段路径 (spec.) | 建议值 | 含义与生产建议 |
| :--- | :--- | :--- |
| `replicas` | `>=2` | 副本数量，保证高可用。 |
| `strategy.type` | `RollingUpdate` | 滚动更新策略。 |
| `resources` | 必填 | 设置 requests/limits 避免资源争抢。 |
| `livenessProbe` | 必填 | 存活探针，探测失败重启容器。 |
| `readinessProbe` | 必填 | 就绪探针，探测成功才接收流量。 |

### StatefulSet - 有状态应用
用于管理 Redis, MySQL 等有状态应用。保证 Pod 的顺序性（0, 1...）和持久化存储的稳定性。
*   **ServiceName**: 必须指定 Headless Service 名称。
*   **VolumeClaimTemplates**: 自动为每个 Pod 创建专属 PVC。

### DaemonSet - 守护进程
确保每个节点运行一个 Pod 副本（如 Fluentd, Node Exporter）。

---

## 2.2 网络与服务发现

### Service 类型对照
*   **ClusterIP**: 仅集群内访问（默认）。
*   **NodePort**: 节点端口映射（30000-32767），用于调试。
*   **LoadBalancer**: 对接云厂商 LB，对外暴露服务。

### Ingress
HTTP/HTTPS 路由规则管理。
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port: { number: 80 }
```

---

## 2.3 配置与存储

### ConfigMap & Secret
*   **ConfigMap**: 存储非敏感配置（配置文件、环境变量）。
*   **Secret**: 存储敏感信息（证书、密码），Base64 编码。
*   **挂载方式**:
    *   `envFrom`: 环境变量注入。
    *   `volumeMounts`: 文件挂载，支持热更新。

---

## 2.4 高级调度与治理

### HPA (水平自动伸缩)
根据 CPU/Memory 利用率自动调整副本数。
```yaml
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource: { name: cpu, target: { averageUtilization: 50 } }
```

### PDB (Pod 干扰预算)
限制维护期间同时不可用的 Pod 数量。
```yaml
kind: PodDisruptionBudget
spec:
  minAvailable: 1
```

### NetworkPolicy (网络策略)
生产环境建议遵循“默认拒绝，按需开放”原则，隔离微服务间流量。

---

# 第二部分：Huawei Ascend 910B AI 训练实战

本部分基于 `AscendJob` CRD 与 Volcano 调度器，详解 NPU 训练任务配置。

## 3.1 快速开始

确保集群已安装 Ascend Device Plugin 与 Volcano。

**单机训练**:
```bash
kubectl apply -f pytorch_singlenodes_acjob_910b.yaml
kubectl logs -f default-test-pytorch-master-0
```

**多机分布式训练**:
```bash
kubectl apply -f pytorch_multinodes_acjob_910b.yaml
# 验证所有节点 (master-0, worker-0) 均为 Running
kubectl get pods -o wide
```

---

## 3.2 核心配置解析 (AscendJob)

### ConfigMap (故障恢复)
用于配合 MindX DL 实现断点续训。
```yaml
kind: ConfigMap
metadata:
  name: reset-config-<job-name> # 必须匹配 Job 名称
data:
  reset.json: |
    { "status": "initializing" }
```

### AscendJob 元数据与标签
| 标签/注解 (Key) | 推荐值 | 说明 |
| :--- | :--- | :--- |
| `framework` | `pytorch` | 指定框架类型。 |
| `ring-controller.atlas` | `ascend-910b` | **核心**: 指定加速器类型。 |
| `fault-scheduling` | `force` | 故障时强制重调度。 |
| `pod-rescheduling` | `on` | 允许 Pod 级重构。 |
| `process-recover-enable` | `on` | 开启进程级原地恢复（更快）。 |

### 资源与环境变量
```yaml
resources:
  limits:
    huawei.com/Ascend910: 8  # 独占一台 910B 服务器
env:
  - name: XDL_IP
    valueFrom: { fieldRef: { fieldPath: status.hostIP } } # 物理 IP 用于通信拓扑
  - name: ASCEND_VISIBLE_DEVICES
    valueFrom: ... # 由调度器自动注入
```

---

## 3.3 存储与挂载详解

**Volume (定义数据源) vs VolumeMounts (定义挂载点)**

| 宿主机路径 | 容器路径 | 作用 |
| :--- | :--- | :--- |
| `/usr/local/Ascend/driver` | `/usr/local/Ascend/driver` | **NPU 驱动** (必须)。 |
| `/dev/shm` | `/dev/shm` | **共享内存** (PyTorch DDP 依赖)。 |
| `/llm_workspace_1P` | `/llm_workspace_1P` | 代码与数据集（统一工作空间）。 |

---

## 3.4 多机分布式训练专题

多机训练采用 **Master + Worker** 架构，需特别注意 Gang Scheduling 和网络配置。

### 1. 架构设计
*   **Master (Rank 0)**: `replicas: 1`
*   **Worker**: `replicas: N-1`

### 2. Gang Scheduling (All-or-Nothing)
防止资源死锁的关键配置。
```yaml
spec:
  runPolicy:
    schedulingPolicy:
      minAvailable: 2  # 必须等于 Master副本数 + Worker副本数
```

### 3. 反亲和性 (Anti-Affinity)
强制 Pod 分散调度到不同物理机。
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: job-name
              operator: In
              values: [ "my-job-name" ]
        topologyKey: kubernetes.io/hostname
```

### 4. 网络配置
*   **`hostNetwork: true`**: 开启主机网络，利用 RoCE 提升通信效率。

---

## 3.5 进阶：超节点亲和性调度

**目标**: 将同一任务的所有 Pod 调度到同一个“超节点”（高速互联的服务器集群）内，最小化跨 Pod 通信延迟。

**配置方法**:
在 `PodGroup` 中添加 `volcano.sh/sp-block` 注解。
*   **值计算公式**: `任务 Pod 总数 * 每个 Pod 的 NPU 请求数`

**示例**: 4 个 Pod，每个 Pod 8 卡 = 32。
```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  annotations:
    volcano.sh/sp-block: "32"
spec:
  minMember: 4
```

---

## 3.6 常见问题与排查

| 现象 | 可能原因 | 排查建议 |
| :--- | :--- | :--- |
| **Pod Pending** | 资源不足 / `minAvailable` 未满足 | 检查集群空闲节点数是否 >= `minAvailable`。 |
| **训练卡死 (Hang)** | 网络不通 / 端口被拦 | 检查 `XDL_IP`、HCCL 端口及防火墙。 |
| **Ranktable Error** | 通信配置错误 | 确认所有节点 `hostNetwork: true`。 |

---

## 4. 附录：自动化验证脚本

保存为 `verify_deployment.sh`，用于验证通用服务部署状态。

```bash
#!/bin/bash
set -e
NAMESPACE="default"
LABEL="app=guestbook"

echo "[INFO] Checking Pod status..."
POD_STATUS=$(kubectl get pods -n $NAMESPACE -l $LABEL -o jsonpath='{.items[*].status.phase}')
if [[ $POD_STATUS == *"Pending"* ]] || [[ $POD_STATUS == *"Failed"* ]]; then
    echo "[ERROR] Pods are not running!"
    exit 1
fi
echo "[SUCCESS] Deployment verified."
```
