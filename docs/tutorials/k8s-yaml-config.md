# Kubernetes YAML 配置全解与最佳实践指南

> **文档版本**: v2.2
> **最后更新**: 2026-02-04
> **适用版本**: Kubernetes v1.20+
> **目标读者**: 运维工程师、SRE、云原生开发者

---

## 目录 (Table of Contents)

[TOC]

---

## 1. 前言

本指南基于生产环境最佳实践，系统性地解析 Kubernetes 核心资源的 YAML 配置。文档以 **Guestbook（留言板）微服务** 为贯穿案例，涵盖从基础负载部署到高级调度、安全治理的全流程。

同时，特别收录了 **Huawei Ascend 910B NPU** 的 AI 训练任务（AscendJob）配置详解，展示 CRD（自定义资源）在高性能计算场景的应用。

### 验证环境
所有示例均在以下环境验证通过：
- **Kubernetes Version**: v1.25.0+
- **OS**: Ubuntu 22.04 LTS / CentOS 7.9
- **Tools**: kubectl, kubeval, jq

---

## 2. 核心工作负载 (Core Workloads)

### 2.1 Deployment - 无状态应用
Deployment 是最常用的工作负载，用于管理无状态应用（如 Web Server）。它处理 Pod 的副本管理、滚动更新和回滚。

#### 核心字段解析
| 字段路径 (spec.)                            | 类型    | 必填   | 默认值        | 含义与生产建议                                                                    |
| :------------------------------------------ | :------ | :----- | :------------ | :-------------------------------------------------------------------------------- |
| `replicas`                                  | Integer | 否     | 1             | 副本数量。**生产建议**: 至少 2 个以保证高可用。                                   |
| `selector`                                  | Object  | **是** | -             | 标签选择器，必须匹配 template 中的 labels。**不可变字段**。                       |
| `strategy.type`                             | String  | 否     | RollingUpdate | 更新策略。可选 `Recreate` 或 `RollingUpdate`。                                    |
| `template.spec.containers`                  | List    | **是** | -             | 容器列表。                                                                        |
| `template.spec.containers[].resources`      | Object  | 否     | -             | **生产必须**: 设置 requests 和 limits 以避免资源争抢 (QoS Guaranteed/Burstable)。 |
| `template.spec.containers[].livenessProbe`  | Object  | 否     | -             | **生产必须**: 存活探针，探测失败重启容器。                                        |
| `template.spec.containers[].readinessProbe` | Object  | 否     | -             | **生产必须**: 就绪探针，探测成功才接收流量。                                      |

#### 实战示例：Guestbook Frontend
```yaml
# guestbook-frontend-deployment.yaml
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
      maxSurge: 25%        # 升级过程中最多可以比原副本数多出的 Pod 数量
      maxUnavailable: 25%  # 升级过程中最多不可用的 Pod 数量
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
          requests:
            cpu: 100m
            memory: 100Mi
          limits:
            cpu: 200m
            memory: 256Mi
        env:
        - name: GET_HOSTS_FROM
          value: "dns"
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
```

#### 验证与操作
```bash
# 1. 创建命名空间
kubectl create ns guestbook

# 2. 应用配置
kubectl apply -f guestbook-frontend-deployment.yaml

# 3. 验证滚动更新
kubectl set image deployment/frontend php-redis=gcr.io/google-samples/gb-frontend:v5 -n guestbook
kubectl rollout status deployment/frontend -n guestbook
```

---

### 2.2 StatefulSet - 有状态应用
用于管理有状态应用（如 Redis, MySQL, Kafka）。它保证 Pod 的顺序性（0, 1, 2...）和持久化存储的稳定性。

#### 核心字段解析
| 字段路径 (spec.)       | 类型   | 必填   | 含义与生产建议                                                           |
| :--------------------- | :----- | :----- | :----------------------------------------------------------------------- |
| `serviceName`          | String | **是** | 关联的 Headless Service 名称，用于生成稳定的 DNS 记录 (pod-0.svc-name)。 |
| `podManagementPolicy`  | String | 否     | `OrderedReady` (默认，按序启动) 或 `Parallel` (并行启动)。               |
| `volumeClaimTemplates` | List   | 否     | 自动为每个 Pod 创建专属的 PVC。                                          |

#### 实战示例：Redis Master (StatefulSet)
```yaml
# redis-master-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-master
  namespace: guestbook
spec:
  serviceName: "redis-master"
  replicas: 1
  selector:
    matchLabels:
      app: redis
      role: master
  template:
    metadata:
      labels:
        app: redis
        role: master
    spec:
      containers:
      - name: master
        image: docker.io/redis:6.0.5
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

---

### 2.3 DaemonSet - 守护进程
确保集群中每个（或符合条件的）Node 上运行一个 Pod 副本。常用于日志收集（Fluentd）、监控（Node Exporter）。

#### 实战示例：Node Exporter
```yaml
# node-exporter-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: kube-system
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true  # 使用宿主机网络
      hostPID: true      # 监控宿主机进程
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.3.1
        ports:
        - containerPort: 9100
          hostPort: 9100
          name: metrics
```

---

### 2.4 CronJob - 定时任务
管理基于时间的 Job，类似 Linux crontab。

#### 核心字段解析
| 字段路径 (spec.)             | 类型    | 含义                                                              |
| :--------------------------- | :------ | :---------------------------------------------------------------- |
| `schedule`                   | String  | Cron 表达式 (如 `0 0 * * *`)。                                    |
| `concurrencyPolicy`          | String  | `Allow` (允许并发), `Forbid` (禁止并发), `Replace` (替换旧任务)。 |
| `successfulJobsHistoryLimit` | Integer | 保留多少个成功的历史记录 (默认 3)。                               |

#### 实战示例：每日备份
```yaml
# db-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: guestbook
spec:
  schedule: "0 2 * * *"  # 每天凌晨 2 点执行
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

## 3. 网络与服务发现 (Network & Discovery)

### 3.1 Service & Ingress

#### Service 类型对照
| 类型           | 说明                               | 适用场景                     |
| :------------- | :--------------------------------- | :--------------------------- |
| `ClusterIP`    | 仅集群内可访问 (默认)。            | 数据库、后端服务。           |
| `NodePort`     | 在每个节点开放端口 (30000-32767)。 | 临时调试、非 HTTP 服务暴露。 |
| `LoadBalancer` | 调用云厂商 API 创建 LB。           | 生产环境对外暴露。           |
| `ExternalName` | 映射到外部 DNS。                   | 引用集群外部服务。           |

#### 实战示例：Frontend Service & Ingress
```yaml
# frontend-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: guestbook
spec:
  type: ClusterIP  # 使用 Ingress 暴露，Service 仅需 ClusterIP
  selector:
    app: guestbook
    tier: frontend
  ports:
  - port: 80
    targetPort: 80

---
# frontend-ingress.yaml
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
            port:
              number: 80
```

---

## 4. 配置与存储 (Config & Storage)

### 4.1 ConfigMap & Secret
用于解耦配置与镜像。

#### 最佳实践
- **ConfigMap**: 存储非敏感信息（配置文件、环境变量）。
- **Secret**: 存储敏感信息（密码、证书）。使用 Base64 编码（注意：不是加密，生产建议配合 Vault 或 KMS）。
- **挂载方式**:
  - 环境变量 (`envFrom`): 简单，但配置变更需重启 Pod。
  - Volume 挂载 (`volumeMounts`): 支持热更新 (Hot Reload)。

#### 实战示例：Redis 配置
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

## 5. 高级调度与治理 (Advanced Scheduling & Governance)

### 5.1 HPA (Horizontal Pod Autoscaler)
根据 CPU/Memory 利用率自动伸缩 Pod 副本数。

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
      target:
        type: Utilization
        averageUtilization: 50
```

### 5.2 PDB (Pod Disruption Budget)
限制在自愿干扰（如节点维护）期间同时不可用的 Pod 数量，保证服务高可用。

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: guestbook
spec:
  minAvailable: 1  # 至少保留 1 个副本可用
  selector:
    matchLabels:
      app: guestbook
      tier: frontend
```

### 5.3 NetworkPolicy (网络策略)
**安全风险提示**: 默认情况下 K8s 网络是互通的。生产环境应遵循“默认拒绝，按需开放”原则。

```yaml
# deny-all-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: guestbook
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

### 5.4 RBAC (Role-Based Access Control)
控制用户或 ServiceAccount 对资源的访问权限。

#### 实战示例：只读权限 Role
```yaml
# readonly-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: guestbook
  name: pod-reader
rules:
- apiGroups: [""] # "" indicates the core API group
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

### 5.5 ResourceQuota & LimitRange
限制命名空间资源总量和默认申请量。

```yaml
# quota-mem-cpu.yaml
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

## 6. 案例详解：Huawei Ascend 910B AI 训练任务 (AscendJob)

本章节基于实际生产环境的配置文件 `pytorch_singlenodes_acjob_910b.yaml`，详细解析基于 **MindX DL** 的 `AscendJob` 自定义资源。该配置用于在 Kubernetes 上调度 NPU 算力进行 PyTorch 训练，支持 **Volcano** 调度器和故障自愈。

### 6.1 配置文件结构
配置文件由两部分组成：
1.  **ConfigMap**: 存储任务重置和故障恢复的状态信息。
2.  **AscendJob**: 定义核心训练任务，包含元数据、调度策略、容器规格等。

### 6.2 详细参数解析

#### A. ConfigMap 配置 (故障恢复状态)
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
    { "status": "initializing" } # 初始状态
```
| 参数              | 含义与作用                                              | 注意事项                                                           |
| :---------------- | :------------------------------------------------------ | :----------------------------------------------------------------- |
| `metadata.name`   | 配置项名称，格式通常为 `reset-config-<job-name>`。      | **必须**与 AscendJob 名称严格对应，MindX DL 控制器依赖此前缀识别。 |
| `data.reset.json` | 存储任务当前的恢复状态（如 initializing, recovering）。 | 该字段由控制器动态更新，初始部署时设为 `initializing`。            |

#### B. AscendJob 元数据与标签 (Metadata & Labels)
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
| 标签/注解 (Key)           | 值 (Value)         | 含义详解                                                                                                           |
| :------------------------ | :----------------- | :----------------------------------------------------------------------------------------------------------------- |
| `framework`               | `pytorch`          | 指定深度学习框架，影响控制器注入的环境变量和启动逻辑。                                                             |
| `ring-controller.atlas`   | `ascend-910b`      | **核心标签**：指定使用的硬件加速器类型（Ascend 910B）。                                                            |
| `tor-affinity`            | `null`             | 交换机亲和性调度标签。`null` 表示不使用。`large-model-schema` 用于大模型，`normal-schema` 用于普通任务。           |
| `fault-scheduling`        | `force`            | 故障调度模式。`force` 表示当检测到故障时，强制进行重调度处理。                                                     |
| `fault-retry-times`       | `10`               | 故障重试次数限制。                                                                                                 |
| `pod-rescheduling`        | `on`               | **Pod 级重调度开关**。当 Pod 异常退出时，允许控制器删除旧 Pod 并创建新 Pod。                                       |
| `process-recover-enable`  | `on`               | **进程级恢复开关**。配合 MindIO，允许训练进程崩溃后在原地（同一个 Pod 内）尝试重启，无需重建 Pod，速度更快。       |
| `subHealthyStrategy`      | `ignore`           | 亚健康节点策略，`ignore` 表示忽略亚健康状态继续调度。                                                              |
| `wait-reschedule-timeout` | `270`              | 进程级恢复等待故障节点重调度的超时时间（秒）。                                                                     |
| `recover-strategy`        | `retry,recover...` | 定义故障恢复的策略链：先尝试重试(retry)，再尝试恢复(recover)，失败则导出日志(dump)并退出(exit)，或降级为弹性训练。 |

#### C. 调度与任务规格 (Spec)
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
| `schedulerName` | `volcano`。使用 Volcano 调度器以支持 **Gang Scheduling** (All-or-Nothing)。避免多机训练时部分节点资源不足导致死锁。 |
| `minAvailable`  | `1`。表示最少需要多少个 Task 运行才能视为任务整体运行。在单机任务中为 1，**多机训练时需修改为节点总数**。           |
| `successPolicy` | `AllWorkers`。所有 Worker 成功完成，整个 Job 才算成功。                                                             |

#### D. 副本规格与容器配置 (ReplicaSpecs)
这是配置最核心的部分，定义了 Pod 的具体运行环境。

**1. 节点选择与网络**
```yaml
nodeSelector:
  qwen: singlenode                     # 业务特定标签（示例）
  host-arch: huawei-arm                # 必须调度到 ARM 架构节点
  accelerator-type: module-a3-8-super-pod # 指定 NPU 模组类型
hostNetwork: true                      # 开启主机网络，提升 NPU 通信效率 (RoCE)
```

**2. 容器与环境变量 (Env)**
```yaml
env:
  - name: LD_LIBRARY_PATH
    value: "..." # 动态链接库路径，包含 Ascend 驱动库
  - name: XDL_IP
    valueFrom: { fieldRef: { fieldPath: status.hostIP } } # 获取宿主机 IP
  - name: ASCEND_VISIBLE_DEVICES
    valueFrom: { fieldRef: { fieldPath: metadata.annotations['huawei.com/Ascend910'] } } # 自动注入分配的 NPU ID
  - name: TTP_PORT
    value: "8000" # MindIO 通信端口
  - name: PROCESS_RECOVER
    value: "on" # 开启进程级别重调度
  - name: MINDIO_WAIT_MINDX_TIME
    value: "60" # MindIO 暂停训练后等待恢复策略下发时间
  - name: POD_IP
    valueFrom: { fieldRef: { fieldPath: status.podIP } } # Pod IP
```

**3. 端口配置 (Ports)**
| 端口   | 名称             | 作用                   |
| :----- | :--------------- | :--------------------- |
| `2222` | `ascendjob-port` | AscendJob 内部通信端口 |
| `8000` | `ttp-port`       | MindIO 通信端口        |
| `9601` | `taskd-port`     | Taskd 通信端口         |

**4. 资源申请 (Resources)**
```yaml
resources:
  limits:
    huawei.com/Ascend910: 8 # 申请 8 张 NPU 卡 (独占一台 910B 服务器)
  requests:
    huawei.com/Ascend910: 8
```

**5. 存储挂载 (Volumes)**
*   `/llm_workspace_1P`: 挂载工作空间（代码和数据集统一挂载）。
*   `/usr/local/Ascend/driver`: **必须**。挂载宿主机的 NPU 驱动。
*   `/dev/shm`: **必须**。共享内存，PyTorch 多进程通信依赖。
*   `/etc/localtime`: 挂载宿主机时间配置，保证时间同步。
*   `/user/restore/reset/config`: 挂载 ConfigMap，用于读取故障恢复状态。

---


### 6.3 超节点亲和性调度 (Super-Node Affinity)

**1. 目标**

对于大规模分布式训练任务（如 LLM 训练），Pod 间的通信效率至关重要。为了最小化网络延迟、最大化训练性能（尤其是张量并行 `TP` 和流水线并行 `PP` 的效率），我们希望将同一个训练任务的所有 Pod 尽可能地调度到同一个“超节点”内。

“超节点”是一个逻辑概念，指由多台通过高速网络（如 RoCE）紧密互联的物理服务器组成的计算集群。将 Pod 调度到同一超节点，可以确保跨 Pod 通信完全利用高速网络，避免普通 TCP/IP 网络带来的性能瓶颈。

**2. 实现机制**

Volcano 调度器提供了超节点亲和性功能，允许将一组 Pod（一个 `PodGroup`）作为一个原子单位进行调度。通过在 `PodGroup` 资源中添加一个特定的 Annotation `volcano.sh/sp-block`，可以强制调度器将该任务的所有 Pod 调度到单一的、资源充足的超节点上。

**3. 配置方法**

`volcano.sh/sp-block` Annotation 的值需要精确设置为该任务所请求的 **NPU 总量**。

*   **计算公式**: `Value = (任务的 Pod 总数) x (每个 Pod 使用的 NPU 数量)`

**4. 配置示例**

假设一个训练任务包含 **4 个 Pod**，每个 Pod 请求 **8 个 NPU** (如华为昇腾 910)。

1.  **计算 NPU 总量**: `4 pods * 8 NPU/pod = 32`
2.  **配置 Annotation**: 在 `PodGroup` 的 `metadata.annotations` 中设置 `volcano.sh/sp-block: "32"`。

**YAML 示例**:

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: my-distributed-training-job
  namespace: default
  annotations:
    # 关键配置：启用超节点亲和性调度
    # 值等于任务所需的 NPU 总量 (4 pods * 8 npu/pod = 32)
    volcano.sh/sp-block: "32"
spec:
  # 任务包含的 Pod 总数，必须与计算 sp-block 值时使用的 Pod 数一致
  minMember: 4
  minResources:
    # 定义每个 Pod 的最小资源，确保调度器能正确计算
    cpu: "32"
    memory: "256Gi"
    huawei.com/Ascend910: "8"
```

**5. 注意事项**

*   **精确匹配**: `volcano.sh/sp-block` 的值必须与 `spec.minMember` 和每个 Pod 的 NPU 请求量精确匹配，否则可能导致调度失败。
*   **功能确认**: 使用此特性前，请确认当前环境部署的 Volcano 版本支持超节点调度功能。
*   **命名可能变化**: `sp-block` 这个名称和具体的 Annotation Key (`volcano.sh/sp-block`) 可能会因 Volcano 的版本或您所在平台的定制化部署而异，请以实际环境为准。


## 7. 进阶指导：配置多机多卡分布式训练

在实际的大模型训练中，单机 8 卡往往无法满足显存和算力需求，需要进行多机多卡（Distributed Training）配置。以下是基于上述 YAML 进行多机扩展的步骤（以 **双机 16 卡** 为例）。

### 7.1 修改副本数量 (Replicas)
将 `replicas` 修改为您需要的节点数量。

```yaml
spec:
  replicaSpecs:
    Master:
      replicas: 2  # 【修改点】设置为 2 或更多
```

### 7.2 调整 Gang Scheduling 策略 (minAvailable)
**关键步骤**：对于多机任务，必须确保所有节点同时就绪才能启动训练，否则可能造成资源死锁。

```yaml
spec:
  runPolicy:
    schedulingPolicy:
      minAvailable: 2  # 【修改点】必须等于 replicas 数量，实现 All-or-Nothing 调度
```

### 7.3 确认反亲和性配置 (PodAntiAffinity)
YAML 模板中已包含 `podAntiAffinity` 配置。在多机训练中，**必须保留**此配置，以确保每个 Pod 调度到不同的物理节点上（每台物理机只有 8 张卡）。

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: job-name
              operator: In
              values:
                - default-test-pytorch  # 确保与 metadata.name 一致
        topologyKey: kubernetes.io/hostname
```
*原理解析*：该配置强制调度器检查：如果某个节点上已经运行了 `job-name=default-test-pytorch` 的 Pod，则不能在该节点上调度第二个 Pod。

### 7.4 分布式环境变量与启动脚本
多机训练依赖 rank table 或 master address 进行组网。
1.  **HCCL 通信**：Ascend 910B 使用 HCCL 进行集合通信。MindX DL 控制器通常会自动生成 `RANK_TABLE_FILE` 或通过环境变量注入集群信息。
2.  **启动命令**：确保 `command` 中的脚本（如 `train_start.sh`）能够处理多机启动逻辑（如设置 `MASTER_ADDR`, `WORLD_SIZE`, `RANK`）。
    *   `WORLD_SIZE`: 对应 `replicas` 数量 * 每节点卡数 (8)。
    *   `RANK`: 当前进程的全局索引。

### 7.5 常见问题排查
*   **Pending 状态**：检查是否有足够的节点满足 `nodeSelector` 和 `resources` (8卡) 要求。
*   **通信失败**：检查 `hostNetwork: true` 是否开启，以及节点间 RoCE 网卡是否互通。
    *   `MASTER_PORT`: 通信端口。
    *   `WORLD_SIZE`: 总进程数（节点数 * 每节点卡数）。
    *   `RANK`: 当前全局进程 ID。

2.  **HCCL 通信配置**：
    华为 Ascend 芯片使用 HCCL 进行通信。确保 `ASCEND_VISIBLE_DEVICES` 正确注入（AscendJob 会自动处理）。

### 7.5 多机配置清单 (Checklist)
1.  [ ] `replicas` 设置为 N (N > 1)。
2.  [ ] `minAvailable` 设置为 N。
3.  [ ] 配置 `podAntiAffinity` 互斥调度。
4.  [ ] 确保底层网络互通（推荐 HostNetwork + RoCE）。
5.  [ ] 训练脚本支持分布式启动（解析 `RANK_TABLE_FILE` 或标准 PyTorch 环境变量）。

---

## 8. 附录：自动化验证脚本

将以下脚本保存为 `verify_guestbook.sh`，用于一键验证上述 Guestbook 部署是否成功。

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

echo "[INFO] Verifying HPA..."
HPA_MIN=$(kubectl get hpa frontend-hpa -n $NAMESPACE -o jsonpath='{.spec.minReplicas}')
if [ "$HPA_MIN" != "2" ]; then
    echo "[ERROR] HPA minReplicas mismatch!"
    exit 1
fi

echo "[SUCCESS] Guestbook deployment verified successfully!"
exit 0
```

### 文档导出
- **PDF**: `pandoc K8s-YAML配置详解.md -o guide.pdf --pdf-engine=wkhtmltopdf`
- **HTML**: `pandoc K8s-YAML配置详解.md -o guide.html`
