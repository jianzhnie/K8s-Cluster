## Huawei Ascend 910B PyTorch 训练实践指南

本文基于实际部署的 `pytorch_singlenodes_acjob_910b.yaml` 与 `pytorch_multinodes_acjob_910b.yaml`，系统讲解 Ascend 910B 在 K8s 上的单机多卡与多机多卡训练配置。核心资源为 **AscendJob (CRD)**，使用 **Volcano** 进行 Gang 调度，并结合 MindX DL 的故障自愈能力。

---

### 快速开始
- 单机训练部署:
  ```bash
  kubectl apply -f pytorch_singlenodes_acjob_910b.yaml
  kubectl get pods -o wide
  kubectl logs -f default-test-pytorch-master-0
  ```
- 多机训练部署:
  ```bash
  kubectl apply -f pytorch_multinodes_acjob_910b.yaml
  kubectl get pods -o wide
  kubectl logs -f default-test-pytorch-master-0
  ```
- 清理:
  ```bash
  kubectl delete -f pytorch_singlenodes_acjob_910b.yaml
  kubectl delete -f pytorch_multinodes_acjob_910b.yaml
  ```

### 1. 配置文件结构
配置文件由两部分组成：
1.  **ConfigMap**: 存储任务重置和故障恢复的状态信息。
2.  **AscendJob**: 定义核心训练任务，包含元数据、调度策略、容器规格等。

### 2. 详细参数解析

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
| `namespace`       | 命名空间。示例使用 `default`。                          | 与 AscendJob 的命名空间保持一致。                                  |
| `labels.reset`    | 重置控制标记。                                          | 设为 `"true"` 以启用初始重置流程。                                 |

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
| `queue`         | Volcano 队列名称。                                                                                                  | 与集群资源队列一致，默认 `default`。 |

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
| 参数                            | 含义与作用                              | 注意事项                                                          |
| :------------------------------ | :-------------------------------------- | :---------------------------------------------------------------- |
| `nodeSelector.qwen`             | 业务标签，用于选择特定节点组。          | 仅示例，按实际业务/机房标签调整。                                 |
| `nodeSelector.host-arch`        | 指定 CPU 架构。Ascend A3 服务器为 ARM。 | 与镜像架构匹配 (ARM)。                                            |
| `nodeSelector.accelerator-type` | 指定 NPU 模组类型。                     | 例如 `module-a3-8-super-pod`；不同机型可能是 `module-910b-8/16`。 |
| `hostNetwork`                   | 使用主机网络，提升集群通信效率与时延。  | 需确保 RoCE 网卡配置与防火墙策略允许端口通信。                    |

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
| 变量名                   | 作用与说明                                                                       |
| :----------------------- | :------------------------------------------------------------------------------- |
| `LD_LIBRARY_PATH`        | 注入 Ascend 驱动库路径，确保训练框架正确加载底层依赖。                           |
| `XDL_IP`                 | 宿主机物理 IP，用于 MindX/HCCL 进行通信拓扑识别。                                |
| `ASCEND_VISIBLE_DEVICES` | 由调度器注解自动注入当前 Pod 分配的 NPU ID；静态 vNPU 或无插件时应删除该变量。   |
| `TTP_PORT`               | MindIO 控制面通信端口，需与容器端口一致。                                        |
| `PROCESS_RECOVER`        | 开启进程级重调度。                                                               |
| `MINDIO_WAIT_MINDX_TIME` | MindIO 暂停后等待策略下发时间；未启用进程级重调度但启用弹性训练时建议设置 ≥ 60。 |
| `POD_IP`                 | Pod IP，用于应用层通信。                                                         |

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
| 字段                   | 含义与说明                                       |
| :--------------------- | :----------------------------------------------- |
| `huawei.com/Ascend910` | Ascend 910B NPU 资源键；值为本 Pod 所需卡数。    |
| `limits/requests`      | 固定为相同值以实现独占卡，避免超售导致性能问题。 |

**5. 存储挂载 (Volumes)**
*   `/job/code`, `/job/data`: 挂载代码和数据集。
*   `/usr/local/Ascend/driver`: **必须**。挂载宿主机的 NPU 驱动。
*   `/dev/shm`: **必须**。共享内存，PyTorch 多进程通信依赖。
*   `/etc/localtime`: 挂载宿主机时间配置，保证时间同步。
*   `/user/restore/reset/config`: 挂载 ConfigMap，用于读取故障恢复状态。
*   `emptyDir.medium: Memory`: 为 `/dev/shm` 提供内存型共享目录，适配多进程通信与缓存。

**6. 其他关键字段**
| 字段                                  | 含义与说明                                                   |
| :------------------------------------ | :----------------------------------------------------------- |
| `restartPolicy: Never`                | 任务型容器不自动重启，交由 MindX 控制器/策略处理故障。       |
| `terminationGracePeriodSeconds: 900`  | 优雅退出等待时间，保证保存检查点与日志。                     |
| `automountServiceAccountToken: false` | 关闭默认 SA token 挂载，降低安全面。                         |
| `imagePullPolicy: IfNotPresent`       | 本地缓存镜像优先，降低拉取开销。                             |
| `command/args`                        | 训练启动脚本入口，示例为 `scripts/train_start.sh`。          |
| `affinity.podAntiAffinity`            | 反亲和，避免同 Job 的多个 Pod 落在同一节点，保障资源独占性。 |

---

## 3. 多机多卡分布式训练 (Multi-Node)

本章节基于实际部署的 **多机配置文件** `pytorch_multinodes_acjob_910b.yaml`，详细解析如何配置跨节点的分布式训练任务。与单机任务不同，多机任务需要协调多个 Pod 的启动、网络通信和角色分配。

### 3.1 多机配置文件结构差异
多机配置的核心区别在于 `replicaSpecs` 的定义。通常采用 **Master + Worker** 的架构模式。

```yaml
spec:
  schedulerName: volcano
  runPolicy:
    schedulingPolicy:
      minAvailable: 2  # 关键点：必须等于 Master + Worker 的总副本数
      queue: default
  successPolicy: AllWorkers
  replicaSpecs:
    Master:
      replicas: 1      # 主节点通常为 1 个
      template: ...
    Worker:
      replicas: 1      # 工作节点数量 (例如双机训练，此处为 1；N 机训练此处为 N-1)
      template: ...
```

### 3.2 详细参数与配置指南

#### A. 调度策略 (Gang Scheduling)
```yaml
spec:
  runPolicy:
    schedulingPolicy:
      minAvailable: 2
```
*   **含义**: `minAvailable` 定义了作业运行所需的最小可用任务数。
*   **配置原则**: 在多机训练中，**必须**设置为所有副本（Master + Worker）的总和。
*   **作用**: 实现 All-or-Nothing 调度。如果集群资源只够启动 1 个 Pod，Volcano 不会调度任何 Pod，防止资源死锁（即 1 个 Pod 等待另一个 Pod 启动，而另一个 Pod 因无资源无法启动）。

#### B. 副本规格 (ReplicaSpecs)
多机任务通常包含 `Master` 和 `Worker` 两种角色。

**1. Master 角色**
*   **职责**: 通常作为 Rank 0，负责初始化进程组、协调训练进度或聚合梯度（视框架而定）。
*   **Replicas**: 固定为 `1`。
*   **配置要点**:
    *   `podAntiAffinity`: 必须配置，确保不与 Worker 调度到同一物理节点（除非单节点多 Pod 场景）。
    *   `hostNetwork: true`: 开启高性能网络。
    *   `accelerator-type`: 根据设备型号设置，例如 910B×8 为 `module-910b-8`，910B×16 为 `module-910b-16`。

**2. Worker 角色**
*   **职责**: 参与计算和梯度同步。
*   **Replicas**: 根据需要的总节点数调整。例如，**双机训练**需 1 Master + 1 Worker，则此处设为 `1`。
*   **配置要点**: 与 Master 保持一致的镜像、资源限制和挂载。

#### C. 关键环境变量 (Env)
在多机 YAML 中，以下环境变量至关重要：

| 变量名                   | 作用                            | 自动注入机制                                  |
| :----------------------- | :------------------------------ | :-------------------------------------------- |
| `XDL_IP`                 | 节点物理 IP，用于集合通信组网。 | `valueFrom: status.hostIP`                    |
| `ASCEND_VISIBLE_DEVICES` | 可见的 NPU 设备 ID。            | 由 Volcano 调度器注解自动注入。               |
| `LD_LIBRARY_PATH`        | 驱动库路径。                    | 必须包含 `/usr/local/Ascend/driver/lib64/...` |
| `TTP_PORT`               | MindIO 通信端口。               | 需与 `ports` 配置一致。                       |

#### D. 存储挂载一致性
多机训练要求所有节点看到的数据和代码必须一致。
*   **代码/数据**: 建议使用 NFS、GlusterFS 等共享存储，或确保 HostPath 下的文件在所有节点完全同步。
*   **示例配置**:
    ```yaml
    volumes:
      - name: code
        hostPath:
          path: /mnt/9w1N7vBPmO3wMAYjqZL/train/MindSpeed-LLM # 确保所有节点该路径存在且内容一致
    ```

### 3.3 多机配置实战步骤 (以双机 16 卡为例)

**第一步：设置副本数**
*   `Master` -> `replicas: 1`
*   `Worker` -> `replicas: 1`
*   总节点数 = 1 + 1 = 2

**第二步：设置 Gang Scheduling**
*   `minAvailable: 2` (确保等于总节点数)

**第三步：配置反亲和性 (PodAntiAffinity)**
在 `Master` 和 `Worker` 的 `template.spec.affinity` 中**都必须**包含以下配置，强制 Pod 分散调度：

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

**第四步：验证网络互通**
*   确保所有节点开启 `hostNetwork: true`。
*   确保节点间 RoCE 网卡 IP 可达。

### 3.4 常见问题排查 Checklist

1.  **Pod 处于 Pending 状态**:
    *   检查集群是否有足够的空闲节点（满足 8 卡/节点要求）。
    *   检查 `minAvailable` 是否满足。如果资源只够 1 个节点，Volcano 不会调度。
2.  **训练卡死 (Hang)**:
    *   检查防火墙是否阻挡了 HCCL 通信端口。
    *   检查 `XDL_IP` 是否正确获取了物理机 IP。
3.  **找不到 Rank 0**:
    *   检查 Master Pod 是否成功启动并处于 Running 状态。

---

## 4. 单机多卡与多机多卡配置要点

### 单机多卡 (Single Node)
- 卡数设置: 在 `resources.{limits,requests}.huawei.com/Ascend910` 设置需要的卡数（如 8）。
- 启动脚本: 确保 `WORLD_SIZE` 为 `本机卡数`，每卡启动一个进程或使用 torchrun 管理。
- 亲和性: 保留 `podAntiAffinity` 以避免同 Job 的多个 Pod 堆叠到同一节点。
- ASCEND_VISIBLE_DEVICES: 使用 Volcano 全卡调度与 ascend-runtime 时启用；静态 vNPU 或未安装插件时删除。

### 多机多卡 (Multi Node)
- 副本数: `Master.replicas=1`，`Worker.replicas=N-1`。
- Gang 调度: `minAvailable = Master + Worker 副本总数`。
- 资源与卡数: 每 Pod 设置 `huawei.com/Ascend910: 8`；总卡数 = 节点数 × 每节点卡数。
- 启动参数: 脚本需正确设置 `MASTER_ADDR`、`MASTER_PORT`、`WORLD_SIZE`、`RANK`。
- 存储一致性: 代码与数据路径在所有节点一致；驱动与 `/dev/shm` 必须挂载。

---

## 5. 常用运维命令
```bash
kubectl get node
kubectl get pods -o wide
kubectl describe pod default-test-pytorch-master-0
kubectl logs -f default-test-pytorch-master-0
kubectl delete -f pytorch_singlenodes_acjob_910b.yaml
kubectl delete -f pytorch_multinodes_acjob_910b.yaml
```
