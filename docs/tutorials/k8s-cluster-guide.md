# Kubernetes 集群配置与 Ascend 910B 训练全指南

> **文档版本**: v4.0
> **最后更新**: 2026-05-10
> **适用范围**: Kubernetes v1.25+ / Huawei Ascend 910B
> **目标读者**: 运维工程师、SRE、AI 算法工程师

---

## 目录

1.  [前言](#1-前言)
2.  [第一部分：Kubernetes 核心配置详解](#第一部分kubernetes-核心配置详解)
    -   [2.1 核心工作负载](#21-核心工作负载)
    -   [2.2 网络与服务发现](#22-网络与服务发现)
    -   [2.3 配置与存储](#23-配置与存储)
    -   [2.4 高级调度与治理](#24-高级调度与治理)
3.  [第二部分：Ascend 910B AI 训练实战](#第二部分huawei-ascend-910b-ai-训练实战)
    -   [3.1 快速开始](#31-快速开始)
    -   [3.2 配置文件结构](#32-配置文件结构)
    -   [3.3 详细参数解析](#33-详细参数解析)
    -   [3.4 存储与挂载详解](#34-存储与挂载详解)
    -   [3.5 多机分布式训练](#35-多机分布式训练)
    -   [3.6 超节点亲和性调度](#36-超节点亲和性调度)
    -   [3.7 单机 vs 多机配置要点](#37-单机-vs-多机配置要点)
    -   [3.8 常见问题与排查](#38-常见问题与排查)
4.  [附录](#4-附录)

---

## 1. 前言

本指南提供从 **通用 Kubernetes 资源管理** 到 **高性能 AI 训练** 的一站式参考。

- **第一部分**：系统性解析 Kubernetes 核心资源的 YAML 配置，以 Guestbook 微服务为贯穿案例，涵盖基础部署到高级治理。
- **第二部分**：深度聚焦 Huawei Ascend 910B NPU 训练场景，基于 `AscendJob` (CRD) 和 Volcano 调度器，详解单机与多机分布式训练。

### 验证环境

- **Kubernetes**: v1.25.0+
- **OS**: Ubuntu 22.04 LTS / CentOS 7.9
- **Tools**: kubectl, jq

---

# 第一部分：Kubernetes 核心配置详解

## 2.1 核心工作负载

### Deployment - 无状态应用

管理无状态应用（如 Web Server），处理副本管理、滚动更新和回滚。

**核心字段解析**:

| 字段路径 (spec.)                            | 必填 | 默认值        | 含义与生产建议                                                                    |
| :------------------------------------------ | :--- | :------------ | :-------------------------------------------------------------------------------- |
| `replicas`                                  | 否   | 1             | 副本数量。**生产建议**: >=2 保证高可用。                                           |
| `selector`                                  | **是** | -             | 标签选择器，必须匹配 template 中的 labels。**不可变字段**。                       |
| `strategy.type`                             | 否   | RollingUpdate | 更新策略。可选 `Recreate` 或 `RollingUpdate`。                                    |
| `template.spec.containers[].resources`      | 否   | -             | **生产必须**: 设置 requests 和 limits 以避免资源争抢。                            |
| `template.spec.containers[].livenessProbe`  | 否   | -             | **生产必须**: 存活探针，探测失败重启容器。                                        |
| `template.spec.containers[].readinessProbe` | 否   | -             | **生产必须**: 就绪探针，探测成功才接收流量。                                      |

**实战示例：Guestbook Frontend**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: guestbook
  labels:
    app: guestbook
    tier: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: guestbook
      tier: frontend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
  template:
    metadata:
      labels:
        app: guestbook
        tier: frontend
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: php-redis
        image: gcr.io/google-samples/gb-frontend:v4
        imagePullPolicy: IfNotPresent
        resources:
          requests: { cpu: 100m, memory: 100Mi }
          limits: { cpu: 200m, memory: 256Mi }
        env:
        - name: GET_HOSTS_FROM
          value: "dns"
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          tcpSocket: { port: 80 }
          initialDelaySeconds: 15
          periodSeconds: 20
```

```bash
# 部署与验证
kubectl create ns guestbook
kubectl apply -f guestbook-frontend-deployment.yaml
kubectl rollout status deployment/frontend -n guestbook
```

### StatefulSet - 有状态应用

管理有状态应用（如 Redis, MySQL, Kafka），保证 Pod 顺序性（0, 1, 2...）和持久化存储稳定性。

| 字段路径 (spec.)       | 必填 | 含义                                                           |
| :--------------------- | :--- | :------------------------------------------------------------- |
| `serviceName`          | **是** | Headless Service 名称，生成稳定 DNS (pod-0.svc-name)。        |
| `podManagementPolicy`  | 否   | `OrderedReady` (按序) 或 `Parallel` (并行)。                   |
| `volumeClaimTemplates` | 否   | 自动为每个 Pod 创建专属 PVC。                                  |

**实战示例：Redis Master**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-master
  namespace: guestbook
spec:
  serviceName: "redis-master"
  replicas: 1
  selector:
    matchLabels: { app: redis, role: master }
  template:
    metadata:
      labels: { app: redis, role: master }
    spec:
      containers:
      - name: master
        image: docker.io/redis:6.0.5
        ports:
        - containerPort: 6379
        resources:
          requests: { cpu: 100m, memory: 100Mi }
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests: { storage: 1Gi }
```

### DaemonSet - 守护进程

确保每个（符合条件的）Node 运行一个 Pod 副本。常用于日志收集 (Fluentd)、监控 (Node Exporter)。

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: kube-system
  labels: { app: node-exporter }
spec:
  selector:
    matchLabels: { app: node-exporter }
  template:
    metadata:
      labels: { app: node-exporter }
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.3.1
        ports:
        - containerPort: 9100
          hostPort: 9100
          name: metrics
```

### CronJob - 定时任务

| 字段路径 (spec.)             | 含义                                                              |
| :--------------------------- | :---------------------------------------------------------------- |
| `schedule`                   | Cron 表达式 (如 `0 0 * * *`)。                                    |
| `concurrencyPolicy`          | `Allow` (允许并发), `Forbid` (禁止), `Replace` (替换旧任务)。     |
| `successfulJobsHistoryLimit` | 保留成功的历史记录数 (默认 3)。                                   |

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: guestbook
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: busybox
            command: ["/bin/sh", "-c", "echo 'Backup done'"]
          restartPolicy: OnFailure
```

---

## 2.2 网络与服务发现

### Service 类型对照

| 类型           | 说明                            | 适用场景                     |
| :------------- | :------------------------------ | :--------------------------- |
| `ClusterIP`    | 仅集群内可访问 (默认)。         | 数据库、后端服务。           |
| `NodePort`     | 每个节点开放端口 (30000-32767)。| 临时调试、非 HTTP 服务暴露。 |
| `LoadBalancer` | 对接云厂商 LB。                 | 生产环境对外暴露。           |
| `ExternalName` | 映射到外部 DNS。                | 引用集群外部服务。           |

### Ingress

HTTP/HTTPS 路由规则管理，配合 Service 暴露服务。

```yaml
# Service
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: guestbook
spec:
  type: ClusterIP
  selector: { app: guestbook, tier: frontend }
  ports:
  - port: 80
    targetPort: 80
---
# Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  namespace: guestbook
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: guestbook.example.com
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

解耦配置与镜像。

- **ConfigMap**: 存储非敏感信息（配置文件、环境变量）。
- **Secret**: 存储敏感信息（密码、证书），Base64 编码。**生产建议配合 Vault 或 KMS**。

**挂载方式**:
- 环境变量 (`envFrom`): 简单，但配置变更需重启 Pod。
- Volume 挂载 (`volumeMounts`): 支持热更新。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: guestbook
data:
  redis.conf: |
    maxmemory 2mb
    maxmemory-policy allkeys-lru
```

---

## 2.4 高级调度与治理

### HPA (水平自动伸缩)

根据 CPU/Memory 利用率自动调整副本数。

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
  namespace: guestbook
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target: { type: Utilization, averageUtilization: 50 }
```

### PDB (Pod 干扰预算)

限制维护期间同时不可用的 Pod 数量。

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: guestbook
spec:
  minAvailable: 1
  selector:
    matchLabels: { app: guestbook, tier: frontend }
```

### NetworkPolicy (网络策略)

生产环境应遵循 **"默认拒绝，按需开放"** 原则。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: guestbook
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

### RBAC (基于角色的访问控制)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: guestbook
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: guestbook
subjects:
- kind: ServiceAccount
  name: default
  namespace: guestbook
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ResourceQuota & LimitRange

限制命名空间资源总量。

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota-mem-cpu
  namespace: guestbook
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
```

---

# 第二部分：Huawei Ascend 910B AI 训练实战

本部分基于 `AscendJob` CRD 与 Volcano 调度器，详解 NPU 训练任务配置。基于实际生产配置文件 `pytorch_singlenodes_acjob_910b.yaml` 和 `pytorch_multinodes_acjob_910b.yaml`。

## 3.1 快速开始

确保集群已安装 Ascend Device Plugin 与 Volcano。

**单机训练**:
```bash
kubectl apply -f pytorch_singlenodes_acjob_910b.yaml
kubectl get pods -o wide
kubectl logs -f default-test-pytorch-master-0
```

**多机分布式训练**:
```bash
kubectl apply -f pytorch_multinodes_acjob_910b.yaml
kubectl get pods -o wide
kubectl logs -f default-test-pytorch-master-0
```

**清理**:
```bash
kubectl delete -f pytorch_singlenodes_acjob_910b.yaml
kubectl delete -f pytorch_multinodes_acjob_910b.yaml
```

---

## 3.2 配置文件结构

配置文件由两部分组成：

1. **ConfigMap**: 存储任务重置和故障恢复的状态信息。
2. **AscendJob**: 定义核心训练任务，包含元数据、调度策略、容器规格等。

---

## 3.3 详细参数解析

### A. ConfigMap (故障恢复状态)

配合 MindX DL 实现断点续训。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: reset-config-default-test-pytorch
  namespace: default
  labels:
    reset: "true"
data:
  reset.json: |
    { "status": "initializing" }
```

| 参数              | 含义与作用                                              | 注意事项                                                           |
| :---------------- | :------------------------------------------------------ | :----------------------------------------------------------------- |
| `metadata.name`   | 格式通常为 `reset-config-<job-name>`。                  | **必须**与 AscendJob 名称严格对应，MindX DL 控制器依赖此前缀识别。 |
| `data.reset.json` | 存储任务恢复状态（initializing, recovering 等）。       | 由控制器动态更新，初始部署设为 `initializing`。                    |
| `labels.reset`    | 重置控制标记。                                          | 设为 `"true"` 以启用初始重置流程。                                 |

### B. AscendJob 元数据与标签

```yaml
apiVersion: mindxdl.gitee.com/v1
kind: AscendJob
metadata:
  name: default-test-pytorch
  labels:
    framework: pytorch
    ring-controller.atlas: ascend-910b
    tor-affinity: "null"
    fault-scheduling: "force"
    fault-retry-times: "10"
    pod-rescheduling: "on"
    process-recover-enable: "on"
    subHealthyStrategy: "ignore"
  annotations:
    wait-reschedule-timeout: "270"
    recover-strategy: "retry,recover,dump,exit,elastic-training"
```

| 标签/注解 (Key)           | 值             | 含义详解                                                                                                           |
| :------------------------ | :------------- | :----------------------------------------------------------------------------------------------------------------- |
| `framework`               | `pytorch`      | 指定深度学习框架，影响控制器注入的环境变量和启动逻辑。                                                             |
| `ring-controller.atlas`   | `ascend-910b`  | **核心标签**：指定硬件加速器类型。                                                                                 |
| `tor-affinity`            | `null`         | 交换机亲和性调度。`null`=不使用，`large-model-schema`=大模型，`normal-schema`=普通任务。                           |
| `fault-scheduling`        | `force`        | 故障调度模式。`force` 表示强制重调度。                                                                             |
| `fault-retry-times`       | `10`           | 故障重试次数限制。                                                                                                 |
| `pod-rescheduling`        | `on`           | **Pod 级重调度**：Pod 异常退出时允许删除旧 Pod 并创建新 Pod。                                                      |
| `process-recover-enable`  | `on`           | **进程级恢复**：配合 MindIO，进程崩溃后在原地重启，无需重建 Pod，速度更快。                                         |
| `subHealthyStrategy`      | `ignore`       | 亚健康节点策略，`ignore`=忽略亚健康状态继续调度。                                                                  |
| `wait-reschedule-timeout` | `270`          | 进程级恢复等待重调度超时时间（秒）。                                                                               |
| `recover-strategy`        | `retry,recover...` | 故障恢复策略链：重试(retry) → 恢复(recover) → 导出日志(dump) → 退出(exit) → 弹性训练。                         |

### C. 调度与任务规格 (Spec)

```yaml
spec:
  schedulerName: volcano
  runPolicy:
    schedulingPolicy:
      minAvailable: 1
      queue: default
  successPolicy: AllWorkers
  replicaSpecs: ...
```

| 参数            | 含义详解                                                                                                            |
| :-------------- | :------------------------------------------------------------------------------------------------------------------ |
| `schedulerName` | `volcano`。使用 Volcano 调度器支持 **Gang Scheduling** (All-or-Nothing)，避免部分节点资源不足导致死锁。              |
| `minAvailable`  | 最少需运行多少个 Task 才视为整体运行。单机为 1，**多机训练时需设为节点总数**。                                       |
| `successPolicy` | `AllWorkers`。所有 Worker 成功完成，整个 Job 才算成功。                                                             |
| `queue`         | Volcano 队列名称，默认 `default`。                                                                                  |

### D. 副本规格与容器配置 (ReplicaSpecs)

#### 1. 节点选择与网络

```yaml
nodeSelector:
  qwen: singlenode                        # 业务标签（示例，按实际调整）
  host-arch: huawei-arm                   # 必须调度到 ARM 架构节点
  accelerator-type: module-a3-8-super-pod # 指定 NPU 模组类型
hostNetwork: true                         # 开启主机网络，利用 RoCE 提升通信效率
```

| 参数                            | 含义与作用                              | 注意事项                                                          |
| :------------------------------ | :-------------------------------------- | :---------------------------------------------------------------- |
| `nodeSelector` 各标签           | 选择特定节点组、CPU 架构、NPU 模组。    | `accelerator-type` 按机型调整，如 `module-910b-8/16`。             |
| `hostNetwork`                   | 使用主机网络，提升通信效率与时延。      | 需确保 RoCE 网卡配置与防火墙策略允许端口通信。                    |

#### 2. 环境变量 (Env)

```yaml
env:
  - name: LD_LIBRARY_PATH
    value: "..."  # Ascend 驱动库路径
  - name: XDL_IP
    valueFrom: { fieldRef: { fieldPath: status.hostIP } }
  - name: ASCEND_VISIBLE_DEVICES
    valueFrom: { fieldRef: { fieldPath: metadata.annotations['huawei.com/Ascend910'] } }
  - name: TTP_PORT
    value: "8000"
  - name: PROCESS_RECOVER
    value: "on"
  - name: MINDIO_WAIT_MINDX_TIME
    value: "60"
  - name: POD_IP
    valueFrom: { fieldRef: { fieldPath: status.podIP } }
```

| 变量名                   | 作用                                                                       |
| :----------------------- | :------------------------------------------------------------------------- |
| `LD_LIBRARY_PATH`        | Ascend 驱动库路径，确保框架正确加载底层依赖。                              |
| `XDL_IP`                 | 宿主机物理 IP，用于 MindX/HCCL 通信拓扑识别。                              |
| `ASCEND_VISIBLE_DEVICES` | 由调度器注解自动注入分配的 NPU ID；静态 vNPU 或无插件时应删除。            |
| `TTP_PORT`               | MindIO 控制面通信端口，需与容器端口配置一致。                              |
| `PROCESS_RECOVER`        | 开启进程级重调度。                                                         |
| `MINDIO_WAIT_MINDX_TIME` | MindIO 暂停后等待策略下发时间；未启用进程级重调度时建议 >=60。             |
| `POD_IP`                 | Pod IP，用于应用层通信。                                                   |

#### 3. 端口配置 (Ports)

| 端口   | 名称             | 作用                   |
| :----- | :--------------- | :--------------------- |
| `2222` | `ascendjob-port` | AscendJob 内部通信端口 |
| `8000` | `ttp-port`       | MindIO 通信端口        |
| `9601` | `taskd-port`     | Taskd 通信端口         |

#### 4. 资源申请 (Resources)

```yaml
resources:
  limits:
    huawei.com/Ascend910: 8   # 独占一台 910B 服务器
  requests:
    huawei.com/Ascend910: 8   # limits/requests 相同值实现独占
```

#### 5. 其他关键字段

| 字段                                  | 含义与说明                                                   |
| :------------------------------------ | :----------------------------------------------------------- |
| `restartPolicy: Never`                | 任务型容器不自动重启，交由 MindX 控制器/策略处理故障。       |
| `terminationGracePeriodSeconds: 900`  | 优雅退出等待时间，保证保存检查点与日志。                     |
| `automountServiceAccountToken: false` | 关闭默认 SA token 挂载，降低安全面。                         |
| `imagePullPolicy: IfNotPresent`       | 本地缓存镜像优先。                                           |
| `command/args`                        | 训练启动脚本入口（如 `scripts/train_start.sh`）。            |

---

## 3.4 存储与挂载详解

在 K8s 中，`volumes` 和 `volumeMounts` 配合使用：

- **`volumes` (Pod 级别)**：定义 **"数据在哪"** — 声明存储卷及其类型（宿主机目录、内存、网络存储等）。
- **`volumeMounts` (Container 级别)**：定义 **"数据挂哪"** — 指定卷在容器内的挂载路径。

### 完整挂载清单

| 宿主机路径 / 卷名                    | 容器路径                          | 作用                                                         |
| :----------------------------------- | :-------------------------------- | :----------------------------------------------------------- |
| `/llm_workspace_1P` (hostPath)       | `/llm_workspace_1P`               | **工作空间**：代码与数据集。                                 |
| `/usr/local/Ascend/driver` (hostPath)| `/usr/local/Ascend/driver`        | **NPU 驱动** (必须)。                                        |
| `emptyDir` (medium: Memory)          | `/dev/shm`                        | **共享内存** (必须)：PyTorch DDP 多进程通信依赖。            |
| `/etc/localtime` (hostPath)          | `/etc/localtime`                  | 时间同步。                                                   |
| ConfigMap `reset-config-*`           | `/user/restore/reset/config`      | 挂载 ConfigMap，读取故障恢复状态。                           |

### 配置示例

```yaml
volumes:
  - name: workspace
    hostPath:
      path: /llm_workspace_1P
  - name: ascend-driver
    hostPath:
      path: /usr/local/Ascend/driver
  - name: shm
    emptyDir:
      medium: Memory
  - name: localtime
    hostPath:
      path: /etc/localtime
  - name: reset-config
    configMap:
      name: reset-config-default-test-pytorch

volumeMounts:
  - name: workspace
    mountPath: /llm_workspace_1P
  - name: ascend-driver
    mountPath: /usr/local/Ascend/driver
  - name: shm
    mountPath: /dev/shm
  - name: localtime
    mountPath: /etc/localtime
  - name: reset-config
    mountPath: /user/restore/reset/config
```

> **多机训练注意**：所有节点的代码和数据路径必须一致。建议使用 NFS/GlusterFS 等共享存储，或确保 HostPath 下的文件在所有节点完全同步。

---

## 3.5 多机分布式训练

多机训练采用 **Master + Worker** 架构，需特别注意 Gang Scheduling 和网络配置。

### 架构设计

- **Master (Rank 0)**: `replicas: 1`，负责初始化进程组、协调训练。
- **Worker**: `replicas: N-1`，参与计算和梯度同步。

```yaml
spec:
  schedulerName: volcano
  runPolicy:
    schedulingPolicy:
      minAvailable: 2      # 必须等于 Master + Worker 副本总数
      queue: default
  successPolicy: AllWorkers
  replicaSpecs:
    Master:
      replicas: 1
      template: ...
    Worker:
      replicas: 1          # 双机=1，N 机=N-1
      template: ...
```

### Gang Scheduling (All-or-Nothing)

**防止资源死锁的关键配置**。`minAvailable` 必须等于所有副本（Master + Worker）的总和。如果集群资源只够启动部分 Pod，Volcano 不会调度任何 Pod。

### 反亲和性 (Anti-Affinity)

**Master 和 Worker 都必须配置**，强制 Pod 分散调度到不同物理节点。

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: job-name
              operator: In
              values:
                - default-test-pytorch  # 必须匹配 Job 名称
        topologyKey: kubernetes.io/hostname
```

### 网络配置

- **`hostNetwork: true`**: 开启主机网络，利用 RoCE 提升通信效率。
- 确保节点间 RoCE 网卡 IP 可达。

### 分布式环境变量

多机训练依赖 rank table 或 master address 进行组网。启动脚本需正确设置：

| 变量           | 说明                              |
| :------------- | :-------------------------------- |
| `MASTER_ADDR`  | Master Pod 的地址。               |
| `MASTER_PORT`  | 通信端口。                        |
| `WORLD_SIZE`   | 总进程数 = 节点数 x 每节点卡数。  |
| `RANK`         | 当前全局进程索引。                |

HCCL 通信：Ascend 910B 使用 HCCL 进行集合通信，MindX DL 控制器通常自动生成 `RANK_TABLE_FILE`。

### 双机 16 卡配置步骤

1. **设置副本数**: `Master.replicas=1`, `Worker.replicas=1`
2. **设置 Gang Scheduling**: `minAvailable: 2`
3. **配置反亲和性**: Master 和 Worker 都添加 `podAntiAffinity`
4. **验证网络互通**: 确保 `hostNetwork: true` 且 RoCE 网卡互通

### 多机配置 Checklist

- [ ] `Master.replicas=1`, `Worker.replicas=N-1`
- [ ] `minAvailable` = Master + Worker 副本总数
- [ ] 配置 `podAntiAffinity` 互斥调度
- [ ] 底层网络互通（推荐 HostNetwork + RoCE）
- [ ] 训练脚本支持分布式启动（解析 `RANK_TABLE_FILE` 或 PyTorch 环境变量）
- [ ] 所有节点的代码和数据路径一致（共享存储或同步）

---

## 3.6 超节点亲和性调度

**目标**：将同一任务的所有 Pod 调度到同一个"超节点"（高速互联的服务器集群）内，最小化跨 Pod 通信延迟，最大化张量并行 (TP) 和流水线并行 (PP) 的效率。

**实现机制**：通过在 `PodGroup` 中添加 `volcano.sh/sp-block` 注解，Volcano 将该任务的所有 Pod 作为一个原子单位调度到单一超节点上。

**值计算公式**: `任务 Pod 总数 x 每个 Pod 的 NPU 数量`

**示例**: 4 个 Pod x 8 卡 = 32

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: my-distributed-training-job
  namespace: default
  annotations:
    volcano.sh/sp-block: "32"    # NPU 总量 = 4 pods * 8 NPU/pod
spec:
  minMember: 4                   # 必须与 Pod 总数一致
  minResources:
    cpu: "32"
    memory: "256Gi"
    huawei.com/Ascend910: "8"
```

**注意事项**:
- `volcano.sh/sp-block` 的值必须与 `spec.minMember` 和每个 Pod 的 NPU 请求量精确匹配，否则调度失败。
- 使用前确认 Volcano 版本支持超节点调度。
- Annotation Key 可能因 Volcano 版本或平台定制而异，以实际环境为准。

---

## 3.7 单机 vs 多机配置要点

### 单机多卡 (Single Node)

- **卡数**: `resources.{limits,requests}.huawei.com/Ascend910` 设置卡数（如 8）。
- **启动**: 确保 `WORLD_SIZE` 为本机卡数，使用 torchrun 管理。
- **亲和性**: 保留 `podAntiAffinity` 避免同 Job 多 Pod 堆叠到同一节点。
- **ASCEND_VISIBLE_DEVICES**: Volcano 全卡调度时启用；静态 vNPU 或未安装插件时删除。
- **minAvailable**: 设为 1。

### 多机多卡 (Multi Node)

- **副本数**: `Master.replicas=1`, `Worker.replicas=N-1`。
- **Gang 调度**: `minAvailable = Master + Worker 副本总数`。
- **资源**: 每 Pod 设 `huawei.com/Ascend910: 8`；总卡数 = 节点数 x 每节点卡数。
- **启动参数**: 脚本需正确设置 `MASTER_ADDR`、`MASTER_PORT`、`WORLD_SIZE`、`RANK`。
- **存储一致性**: 代码与数据路径在所有节点一致；驱动与 `/dev/shm` 必须挂载。

---

## 3.8 常见问题与排查

| 现象                    | 可能原因                          | 排查建议                                                              |
| :---------------------- | :-------------------------------- | :-------------------------------------------------------------------- |
| **Pod Pending**         | 资源不足 / `minAvailable` 未满足  | 检查集群空闲节点数是否 >= `minAvailable`。                            |
| **训练卡死 (Hang)**     | 网络不通 / 端口被拦               | 检查 `XDL_IP`、HCCL 端口及防火墙；确认 `hostNetwork: true`。         |
| **Ranktable Error**     | 通信配置错误                      | 确认所有节点 `hostNetwork: true` 且 RoCE 网卡互通。                   |
| **找不到 Rank 0**       | Master Pod 未成功启动             | 检查 Master Pod 是否 Running；查看 `kubectl describe pod`。           |
| **镜像拉取失败**        | 镜像不存在 / 网络不通             | 检查镜像名称、`imagePullPolicy`，确认节点可访问镜像仓库。             |

---

## 4. 附录

### 4.1 常用运维命令

```bash
# 集群状态
kubectl get node
kubectl get pods -o wide

# 任务调试
kubectl describe pod default-test-pytorch-master-0
kubectl logs -f default-test-pytorch-master-0

# 清理任务
kubectl delete -f pytorch_singlenodes_acjob_910b.yaml
kubectl delete -f pytorch_multinodes_acjob_910b.yaml
```

### 4.2 自动化验证脚本

**Guestbook 部署验证** (`verify_guestbook.sh`):

```bash
#!/bin/bash
set -e

NAMESPACE="guestbook"

echo "[INFO] Checking Pod status..."
POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=guestbook -o jsonpath='{.items[*].status.phase}')
if [[ $POD_STATUS == *"Pending"* ]] || [[ $POD_STATUS == *"Failed"* ]]; then
    echo "[ERROR] Pods are not running!"
    kubectl get pods -n $NAMESPACE
    exit 1
fi

echo "[INFO] Checking Service endpoints..."
ENDPOINTS=$(kubectl get ep frontend -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}')
if [ -z "$ENDPOINTS" ]; then
    echo "[ERROR] Frontend service has no endpoints!"
    exit 1
fi

echo "[SUCCESS] Guestbook deployment verified."
```

### 4.3 文档导出

```bash
# PDF
pandoc k8s-cluster-guide.md -o guide.pdf --pdf-engine=wkhtmltopdf
# HTML
pandoc k8s-cluster-guide.md -o guide.html
```
