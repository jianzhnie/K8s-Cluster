# K8s 集群常用命令速查手册 (V2.0)

本手册汇集了 Kubernetes 集群日常运维、开发调试及故障处理的常用命令。

## 目录

- [1. 基础配置与环境](#1-基础配置与环境)
- [2. 集群与节点管理](#2-集群与节点管理)
  - [2.1 节点查询与监控](#21-节点查询与监控)
  - [2.2 Label 标签管理](#22-label-标签管理)
  - [2.3 Taint 污点管理](#23-taint-污点管理)
  - [2.4 节点调度控制](#24-节点调度控制)
- [3. Pod 与容器管理](#3-pod-与容器管理)
  - [3.1 Pod 基础操作](#31-pod-基础操作)
  - [3.2 查找 Pod 所在节点](#32-查找-pod-所在节点)
  - [3.3 查找 Job 运行节点](#33-查找-job-运行节点)
  - [3.4 Pod 调试排障](#34-pod-调试排障)
- [4. 工作负载 (Deployments/Jobs)](#4-工作负载-deploymentsjobs)
- [5. 网络与服务](#5-网络与服务)
- [6. 配置与存储](#6-配置与存储)
- [7. 故障排查与清理](#7-故障排查与清理)
  - [7.1 强制删除卡死资源](#71-强制删除卡死资源)
  - [7.2 物理节点深度清理](#72-物理节点深度清理)
  - [7.3 Ansible 批量清理](#73-ansible-批量清理)
  - [7.4 常见问题速查](#74-常见问题速查)
- [8. AscendJob 训练任务专用](#8-ascendjob-训练任务专用)

---

## 1. 基础配置与环境

管理 kubectl 配置、上下文及 API 资源。

| 命令                                | 说明                               | 示例                                     |
| :---------------------------------- | :--------------------------------- | :--------------------------------------- |
| `kubectl config view`               | 查看当前 kubeconfig 配置           |                                          |
| `kubectl config get-contexts`       | 查看所有上下文                     |                                          |
| `kubectl config use-context <name>` | 切换上下文（集群环境）             | `kubectl config use-context dev-cluster` |
| `kubectl api-resources`             | 列出所有支持的 API 资源类型        | `kubectl api-resources \| grep ascend`   |
| `kubectl explain <resource>`        | 查看资源字段文档（相当于 man 手册） | `kubectl explain pod.spec.containers`    |

**通用参数：**

| 参数              | 说明                                                      |
| :---------------- | :-------------------------------------------------------- |
| `-n <namespace>`  | 指定命名空间（默认 `default`），`-A` 或 `--all-namespaces` 表示所有 |
| `-o <format>`     | 输出格式：`wide`（详细）、`yaml`、`json`、`name`（仅名称） |
| `--dry-run=client`| 试运行，不实际提交，常配合 `-o yaml` 生成模板             |
| `-l <selector>`   | 标签选择器过滤，支持 `=`, `!=`, `!key`, `in`, `notin`     |
| `-w` / `--watch`  | 持续监听资源变化                                           |

**命名空间管理：**

```bash
kubectl get ns                              # 查看所有命名空间
kubectl create ns <name>                    # 创建命名空间
kubectl delete ns <name>                    # 删除命名空间（会删除其下所有资源）
kubectl get pods -n <ns>                    # 查看指定命名空间的 Pod
kubectl get pods -A                         # 查看所有命名空间的 Pod
```

---

## 2. 集群与节点管理

### 2.1 节点查询与监控

| 命令                           | 说明                            | 示例                                        |
| :----------------------------- | :------------------------------ | :------------------------------------------ |
| `kubectl cluster-info`         | 查看控制平面组件状态            |                                             |
| `kubectl get nodes -o wide`    | 查看节点 IP、内核版本、OS 等    |                                             |
| `kubectl top node`             | **实时监控**节点 CPU/内存使用率 |                                             |
| `kubectl describe node <name>` | 查看节点分配资源、污点、事件    | `kubectl describe node bms1889`             |

**仅获取节点名列表：**

```bash
# 推荐：不依赖列宽对齐
kubectl get node -o name | cut -d/ -f2

# 自定义列名
kubectl get node --no-headers -o custom-columns=NAME:.metadata.name
```

**查看节点资源分配情况：**

```bash
# 查看所有节点的 CPU/内存分配与可分配量
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
CPU-ALLOC:.status.allocatable.cpu,\
CPU-USED:.status.capacity.cpu,\
MEM-ALLOC:.status.allocatable.memory,\
MEM-USED:.status.capacity.memory

# 快速查看节点资源压力（MemoryPressure/DiskPressure/PIDPressure）
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.status=="True")].type}{"\n"}{end}'
```

### 2.2 Label 标签管理

**标签选择器（Label Selector）语法速查：**

| 语法                  | 含义                       | 示例                               |
| :-------------------- | :------------------------- | :--------------------------------- |
| `key=value`           | 等于                       | `-l env=prod`                      |
| `key!=value`          | 不等于                     | `-l env!=staging`                  |
| `key`                 | 存在该 key                 | `-l environment`                   |
| `!key`                | 不存在该 key               | `-l '!environment'`                |
| `key in (a,b)`        | 值在集合中                 | `-l 'env in (prod,staging)'`      |
| `key notin (a,b)`     | 值不在集合中               | `-l 'env notin (dev,test)'`       |

> 多个条件用逗号分隔表示 AND 关系：`-l env=prod,tier=frontend`

**单节点操作：**

```bash
# 打标签
kubectl label node <node-name> <key>=<value>

# 覆盖已有标签
kubectl label node <node-name> <key>=<value> --overwrite

# 删除标签（key 后加 `-`）
kubectl label node <node-name> <key>-
```

**批量打标签：**

```bash
# 按节点名范围（bms 格式）
kubectl label nodes $(seq -f "bms%04g" 1 448) <key>=<value> --overwrite

# 对集群中所有真实存在的节点打标签（推荐）
kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name \
  | xargs -r -n1 -I{} kubectl label node {} <key>=<value> --overwrite

# 仅对 bms 格式节点打标签
kubectl get nodes -o name | cut -d/ -f2 | grep -E '^bms[0-9]{4}$' \
  | xargs -r -n1 -I{} kubectl label node {} <key>=<value> --overwrite

# Dry-run 预览（不实际执行）
kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name \
  | xargs -r -n1 -I{} kubectl label node {} <key>=<value> --overwrite --dry-run=server -o yaml
```

> **要点：** `-I{}` 将节点名插入资源位置，`-n1` 保证每次只处理一个节点避免参数拼接问题。

**查询标签：**

```bash
# 查看所有节点的标签
kubectl get nodes --show-labels

# 查看特定节点的标签
kubectl get nodes <name1> <name2> --show-labels

# 查找打过特定 Label 的节点
kubectl get nodes -l disktype=ssd

# 查找**不带**某个 Label 的节点
kubectl get nodes -l '!environment'
```

**统计集群中所有 Label Key（去重）：**

```bash
# 使用 jq
kubectl get nodes -o json | jq -r '.items[].metadata.labels | keys[]' | sort | uniq

# 无 jq 的替代方案
kubectl get nodes --show-labels | grep -oP '(?<=,|^)[^=,]+(?==)' | sort | uniq
```

### 2.3 Taint 污点管理

污点可以从调度层面将节点标记为"坏节点"，普通 Pod 不会再调度上去。

**Taint Effect 对比：**

| Effect          | 对新 Pod            | 对已有 Pod          | 适用场景               |
| :-------------- | :------------------ | :------------------ | :--------------------- |
| `NoSchedule`    | 不调度              | 不受影响            | 标记坏节点（推荐）     |
| `NoExecute`     | 不调度              | **驱逐不容忍的 Pod** | 节点故障、内核升级     |
| `PreferNoSchedule` | 尽量不调度（软限制） | 不受影响            | 优先级较低的隔离       |

**单节点操作：**

```bash
# 添加污点
kubectl taint nodes <node-name> node-status=bad:NoSchedule
kubectl taint nodes <node-name> node-status=bad:NoExecute

# 移除污点（key 后加 `-`）
kubectl taint nodes <node-name> node-status-

# 查看节点污点
kubectl describe node <node-name> | grep -A5 Taints
```

**批量打污点：**

```bash
# 按节点名范围添加
kubectl taint nodes $(seq -f "bms%04g" 385 448) node-status=bad:NoSchedule --overwrite

# 按节点名范围移除
kubectl taint nodes $(seq -f "bms%04g" 385 448) node-status-
```

**让特定 Pod 容忍污点（在 Pod YAML 中添加）：**

```yaml
tolerations:
  - key: "node-status"
    operator: "Equal"
    value: "bad"
    effect: "NoSchedule"
```

> `operator` 支持 `Equal`（精确匹配 value）和 `Exists`（只要 key 存在即匹配，可省略 value）。

### 2.4 节点调度控制

| 方式                     | 命令                                                    | 适用场景                     |
| :----------------------- | :------------------------------------------------------ | :--------------------------- |
| **禁止调度**（维护模式） | `kubectl cordon <node>`                                 | 短期维护                     |
| **恢复调度**             | `kubectl uncordon <node>`                               | 维护结束                     |
| **驱逐 Pod**             | `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` | 节点清空维护           |
| **Taint NoSchedule**     | `kubectl taint nodes <node> node-status=bad:NoSchedule` | 标记坏节点（推荐）           |
| **Taint NoExecute**      | `kubectl taint nodes <node> node-status=bad:NoExecute`  | 标记坏节点 + 驱逐现有 Pod    |

> **选择建议：** 应急/短期维护用 `cordon/drain`；长期标记坏节点用 Taint；如有统一 CI/CD 模板体系，可额外用 Label + `nodeAffinity` 做精细控制。

**Label + nodeAffinity 方式（需统一 YAML 模板）：**

```bash
kubectl label node <node-name> node-status=bad
```

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-status
              operator: NotIn
              values: ["bad"]
```

---

## 3. Pod 与容器管理

### 3.1 Pod 基础操作

| 命令                                          | 说明                                  | 示例                                          |
| :-------------------------------------------- | :------------------------------------ | :-------------------------------------------- |
| `kubectl get pods -A`                         | 查看所有 Pod                          |                                               |
| `kubectl run <name> --image=<img>`            | 快速启动一个 Pod                      | `kubectl run nginx --image=nginx:alpine`      |
| `kubectl logs <pod> [-c <container>]`         | 查看日志（`-f` 实时，`-p` 上一个实例） | `kubectl logs -f my-pod -c worker`            |
| `kubectl exec -it <pod> -- <cmd>`             | **进入容器**或执行命令                | `kubectl exec -it my-pod -- bash`             |
| `kubectl cp <local> <pod>:<remote>`           | 文件复制（双向）                      | `kubectl cp ./data.csv my-pod:/data/`         |
| `kubectl port-forward <pod> <local>:<remote>` | 端口转发（本地访问 Pod 服务）          | `kubectl port-forward redis-master 6379:6379` |
| `kubectl delete pod <name>`                   | 删除 Pod                              | `kubectl delete pod my-pod --grace-period=0`  |
| `kubectl get pods --show-labels -A`           | 查看所有 Pod 及其标签                 |                                               |

**常用过滤技巧：**

```bash
# 按状态过滤 Pod
kubectl get pods -A --field-selector=status.phase=Pending
kubectl get pods -A --field-selector=status.phase=Failed

# 按标签过滤
kubectl get pods -l app=nginx -A
kubectl get pods -l 'app in (nginx,redis)' -A

# 按节点过滤
kubectl get pods -A --field-selector=spec.nodeName=<node-name>

# 按重启次数排序（找出最不稳定的 Pod）
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'

# 按创建时间排序
kubectl get pods -A --sort-by='.metadata.creationTimestamp'
```

### 3.2 查找 Pod 所在节点

```bash
# 知道 Pod 名字和命名空间（最常用）
kubectl get pod <pod-name> -n <ns> -o wide

# 仅获取节点名（适合脚本）
kubectl get pod <pod-name> -o jsonpath='{.spec.nodeName}'

# 不知道命名空间，全局搜索
kubectl get pods -A --field-selector=metadata.name=<pod-name> -o wide

# 通过标签查找一组 Pod 所在节点
kubectl get pods -l app=nginx -o wide
```

**高级用法 — 给运行特定 Pod 的节点打标签：**

```bash
kubectl get pods -l app=my-app -o jsonpath='{.items[*].spec.nodeName}' \
  | tr ' ' '\n' | sort | uniq \
  | xargs -I {} kubectl label node {} app=my-app-node --overwrite
```

### 3.3 查找 Job 运行节点

```bash
# 指定命名空间，按 Pod 名前缀筛选，输出去重的节点列表
kubectl get pod -n <ns> \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
  | grep '^<job-name-prefix>' | awk '{print $2}' | sort -u

# 全局搜索，输出 NS / Pod / Node 对应关系
kubectl get pod -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
  | awk '$2 ~ /<job-name-prefix>/ {print $1,$2,$3}'
```

**实用组合 — 筛选"打了标签但没有运行特定 Pod"的空闲节点：**

```bash
comm -23 \
  <(kubectl get nodes -l <label-key> -o custom-columns=NAME:.metadata.name --no-headers | sort -u) \
  <(kubectl get pod -A -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
    | awk '$1 ~ /^<job-name-prefix>/ {print $2}' | sort -u)
```

### 3.4 Pod 调试排障

**Pod 生命周期状态速查：**

| 状态          | 含义                         | 排查方向                         |
| :------------ | :--------------------------- | :------------------------------- |
| `Pending`     | 未调度或镜像拉取中           | `kubectl describe pod` 看 Events |
| `ContainerCreating` | 容器创建中（拉镜像/挂载卷） | `kubectl describe pod` 看 Events |
| `CrashLoopBackOff` | 容器启动后崩溃，反复重启    | `kubectl logs <pod> -p` 看上次日志 |
| `ImagePullBackOff` | 镜像拉取失败                | 检查镜像名/Secret/网络           |
| `OOMKilled`   | 内存溢出被杀                 | 增大 resources.limits.memory     |
| `Completed`   | 容器正常退出                 | Job 类型任务正常终态             |

**排障命令：**

```bash
# 查看 Pod 事件（调度失败、镜像拉取、卷挂载等问题）
kubectl describe pod <pod-name> -n <ns>

# 查看上次崩溃的日志（Pod 重启后仍可查看）
kubectl logs <pod-name> -n <ns> -p

# 查看特定容器的日志（多容器 Pod）
kubectl logs <pod-name> -n <ns> -c <container-name>

# 实时跟踪日志
kubectl logs -f <pod-name> -n <ns> --tail=100

# 进入容器排查
kubectl exec -it <pod-name> -n <ns> -- bash
kubectl exec -it <pod-name> -n <ns> -- sh    # 无 bash 时用 sh

# 查看 Pod 资源使用（需要 metrics-server）
kubectl top pod <pod-name> -n <ns>
kubectl top pods -A --sort-by=memory          # 按内存排序
kubectl top pods -A --sort-by=cpu             # 按 CPU 排序
```

---

## 4. 工作负载 (Deployments/Jobs)

管理应用副本、滚动更新与批处理任务。

| 命令                                       | 说明                  | 示例                                            |
| :----------------------------------------- | :-------------------- | :---------------------------------------------- |
| `kubectl get deploy,sts,ds`                | 查看各类工作负载状态  |                                                 |
| `kubectl scale deploy <name> --replicas=N` | **手动扩缩容**        | `kubectl scale deploy/nginx --replicas=3`       |
| `kubectl rollout status deploy <name>`     | 查看滚动更新进度      |                                                 |
| `kubectl rollout undo deploy <name>`       | **回滚**到上一个版本  |                                                 |
| `kubectl rollout restart deploy <name>`    | 重启所有 Pod（无中断） | `kubectl rollout restart deploy/nginx`          |
| `kubectl create job --from=cronjob/<name>` | 手动触发 CronJob      | `kubectl create job test --from=cronjob/backup` |

**滚动更新管理：**

```bash
# 查看滚动更新历史
kubectl rollout history deploy <name>

# 回滚到指定版本
kubectl rollout undo deploy <name> --to-revision=2

# 暂停滚动更新（可用于金丝雀发布）
kubectl rollout pause deploy <name>

# 恢复滚动更新
kubectl rollout resume deploy <name>
```

**Job 管理：**

```bash
# 查看 Job 及关联 Pod
kubectl get job <name> -o wide

# 查看 Job 运行的 Pod（Job 创建的 Pod 名为 <job-name>-<random-suffix>）
kubectl get pods -l job-name=<name>

# 删除 Job（级联删除关联 Pod）
kubectl delete job <name>

# 查看失败的 Job
kubectl get jobs -A --field-selector=status.successful!=1
```

---

## 5. 网络与服务

调试 Service 和 Ingress。

| 命令                           | 说明                                          | 示例                                                    |
| :----------------------------- | :-------------------------------------------- | :------------------------------------------------------ |
| `kubectl get svc,ep`           | 查看 Service 及对应的 Endpoints（后端 Pod IP） |                                                         |
| `kubectl get ingress`          | 查看 Ingress 路由规则                         |                                                         |
| `kubectl expose deploy <name>` | 快速为 Deployment 创建 Service                | `kubectl expose deploy nginx --port=80 --type=NodePort` |
| `kubectl describe svc <name>`  | 排查 Service 无法连通的问题                   |                                                         |

**网络调试：**

```bash
# 查看 Service 详情（关联 Selector、ClusterIP、Port 映射）
kubectl describe svc <name> -n <ns>

# 查看 Endpoints（确认后端 Pod 是否被正确关联）
kubectl get endpoints <svc-name> -n <ns>

# 检查 Endpoints 是否为空（Service selector 与 Pod label 不匹配的常见问题）
kubectl get ep <svc-name> -n <ns> -o yaml | grep -A5 subsets

# 临时启动一个调试 Pod 测试网络连通性
kubectl run netshoot --image=nicolaka/netshoot --rm -it -- bash
# 在调试 Pod 内可使用 curl、dig、nslookup、ping 等工具

# 端口转发到本地调试
kubectl port-forward svc/<svc-name> <local-port>:<svc-port> -n <ns>
kubectl port-forward deploy/<name> <local-port>:<container-port> -n <ns>
```

---

## 6. 配置与存储

管理 ConfigMap、Secret、PVC、PV。

| 命令                            | 说明                                          | 示例                                                          |
| :------------------------------ | :-------------------------------------------- | :------------------------------------------------------------ |
| `kubectl get cm,secret`         | 查看配置与密钥                                |                                                               |
| `kubectl create secret generic` | 创建密钥                                      | `kubectl create secret generic db-pass --from-literal=pw=123` |
| `kubectl get pvc,pv`            | 查看持久化卷状态                              |                                                               |
| `kubectl describe pvc <name>`   | 排查 PVC Pending 原因（如 storageclass 问题） |                                                               |

**ConfigMap 操作：**

```bash
# 从字面值创建
kubectl create cm <name> --from-literal=key1=val1 --from-literal=key2=val2

# 从文件创建
kubectl create cm <name> --from-file=config.yaml

# 从目录创建（目录中每个文件为一个 key）
kubectl create cm <name> --from-file=configs/

# 查看 ConfigMap 内容
kubectl get cm <name> -o yaml

# 编辑 ConfigMap（会打开编辑器）
kubectl edit cm <name>
```

**PVC/PV 排障：**

```bash
# 查看 PVC 状态
kubectl get pvc -A

# 查看 PVC 事件（Pending 原因：无可用 PV、SC 不存在、配额不足等）
kubectl describe pvc <name> -n <ns>

# 查看 PV 回收策略和状态
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
CAPACITY:.spec.capacity.storage,\
STATUS:.status.phase,\
CLAIM:.spec.claimRef.name,\
STORAGECLASS:.spec.storageClassName,\
RECLAIM:.spec.persistentVolumeReclaimPolicy
```

---

## 7. 故障排查与清理

### 7.1 强制删除卡死资源

```bash
# 强制删除单个 Pod（跳过优雅退出期）
kubectl delete pod <pod-name> -n <ns> --force --grace-period=0

# 批量删除所有 Terminating 状态的 Pod
kubectl get pods -A | grep Terminating \
  | awk '{print $2 " --namespace=" $1}' | xargs -I {} kubectl delete pod {} --force --grace-period=0

# 删除卡死的 NS（删除 finalizer）
kubectl get ns <ns> -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw /api/v1/namespaces/<ns>/finalize -f -
```

### 7.2 物理节点深度清理

**场景：** API 对象已删，但节点上显存未释放或进程残留。

```bash
# 1. 登录物理节点
ssh root@<node-ip>

# 2a. 清理残留容器（Docker 环境）
docker ps | grep <keyword> | awk '{print $1}' | xargs docker rm -f

# 2b. 清理残留容器（Containerd/CRI 环境）
crictl ps -a | grep <keyword> | awk '{print $1}' | xargs -I {} crictl stop {} && crictl rm {}

# 3. 查找占用 Ascend NPU 设备的进程
fuser -v /dev/davinci*

# 4. 强制杀掉残留训练进程（慎用）
ps -ef | grep python | grep <task-keyword> | awk '{print $2}' | xargs kill -9
```

### 7.3 Ansible 批量清理

适用于多机集群快速清理，无需逐个登录节点。

```bash
# 通用模板：替换 inventory 文件名和过滤关键字
ansible -i <inventory-file> all -m shell -a \
  'bash -c "crictl ps -a | grep <keyword> | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'
```

**示例：**

```bash
# 清理 llama31 相关容器
ansible -i host-kuang73-74 all -m shell -a \
  'bash -c "crictl ps -a | grep llama31 | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'

# 清理 deepseek 相关容器
ansible -i host-train-1024npu all -m shell -a \
  'bash -c "crictl ps -a | grep deepseek | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'
```

### 7.4 常见问题速查

| 现象                          | 排查命令                                          | 常见原因                         |
| :---------------------------- | :------------------------------------------------ | :------------------------------- |
| Pod 一直 Pending              | `kubectl describe pod <name>`                     | 资源不足、节点选择器不匹配、PVC Pending |
| Pod CrashLoopBackOff          | `kubectl logs <name> -p`                          | 应用启动失败、配置错误、OOM      |
| Pod ImagePullBackOff          | `kubectl describe pod <name>`                     | 镜像名错误、Secret 缺失、网络不通 |
| Service 无法访问              | `kubectl get ep <svc>`                            | Selector 与 Pod Label 不匹配     |
| PVC 一直 Pending              | `kubectl describe pvc <name>`                     | 无可用 PV、SC 不存在、配额不足   |
| 节点 NotReady                 | `kubectl describe node <name>`                    | kubelet 异常、网络不通、磁盘满   |
| Pod Terminating 卡死          | `kubectl delete pod <name> --force --grace-period=0` | finalizer 未移除、节点失联       |
| 节点上 NPU 未释放             | `fuser -v /dev/davinci*`                          | 僵尸进程未清理                   |

---

## 8. AscendJob 训练任务专用

Huawei Ascend 910B AI 训练任务（MindX DL）核心操作。

| 命令                                                   | 说明                               |
| :----------------------------------------------------- | :--------------------------------- |
| `kubectl apply -f pytorch_singlenodes_acjob_910b.yaml` | 提交单机训练任务                   |
| `kubectl apply -f pytorch_multinodes_acjob_910b.yaml`  | 提交多机训练任务                   |
| `kubectl get ascendjob`                                | 查看任务总览（状态/运行时长）      |
| `kubectl describe ascendjob <name>`                    | **查看任务事件**（报错/重调度信息） |
| `kubectl delete ascendjob <name>`                      | 删除任务（自动级联删除 Pods）      |

**AscendJob 标准调试流程：**

```
1. 提交任务    kubectl apply -f <yaml>
2. 监控启动    kubectl get pods -l job-name=<name> -w
3. 查看日志
   - Master    kubectl logs -f <name>-master-0
   - Worker    kubectl logs -f <name>-worker-0
4. 故障排查
   - Pending   kubectl describe pod <pod-name>  （查看调度失败原因）
   - 卡住      kubectl exec -it <pod> -- bash   （查看 /var/log/npu 或应用日志）
5. 清理环境    kubectl delete ascendjob <name>   （推荐 delete -f <yaml>）
```

**AscendJob 常见问题：**

| 现象                       | 排查方向                                              |
| :------------------------- | :---------------------------------------------------- |
| 任务一直 Pending           | NPU 资源不足、节点污点、devicePlugin 未就绪            |
| Master 启动但 Worker 卡住  | 检查 HCCL 配置、节点间网络、NPU 设备状态                |
| 训练报 `HCCL E0001`       | NPU 间通信失败，检查节点间 RDMA 网络                    |
| Pod 内看不到 NPU 设备      | devicePlugin 未正确注入，`kubectl describe pod` 检查资源 |
| 任务完成后 Pod 被立即删除  | 修改 `ttlSecondsAfterFinished` 或及时查看日志            |

**快速查看集群 NPU 使用情况：**

```bash
# 查看各节点 NPU 资源总量与已分配量
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
NPU-ALLOC:.status.allocatable['ascend-910b'],\
NPU-CAP:.status.capacity['ascend-910b']
```
