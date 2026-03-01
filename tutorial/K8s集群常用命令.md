# K8s 集群常用命令速查手册 (V2.0)

本手册汇集了 Kubernetes 集群日常运维、开发调试及故障处理的常用命令。

## 目录
- [K8s 集群常用命令速查手册 (V2.0)](#k8s-集群常用命令速查手册-v20)
  - [目录](#目录)
  - [1. 基础配置与环境](#1-基础配置与环境)
  - [2. 集群与节点管理](#2-集群与节点管理)
    - [2.1 给节点打Label](#21-给节点打label)
    - [2.2 标记坏节点并禁止调度](#22-标记坏节点并禁止调度)
    - [2.3 查看所有节点的 Label](#23-查看所有节点的-label)
      - [1. 查看所有节点的 Label](#1-查看所有节点的-label)
      - [2. 统计集群中出现过的所有 Label Key（去重）](#2-统计集群中出现过的所有-label-key去重)
      - [3. 查找打过特定 Label 的节点](#3-查找打过特定-label-的节点)
      - [4. 查找 Pod 的 Label](#4-查找-pod-的-label)
  - [3. Pod 与容器管理](#3-pod-与容器管理)
  - [4. 工作负载 (Deployments/Jobs)](#4-工作负载-deploymentsjobs)
  - [5. 网络与服务](#5-网络与服务)
  - [6. 配置与存储](#6-配置与存储)
  - [7. 故障排查与清理](#7-故障排查与清理)
    - [7.1 强制删除 API 对象 (Terminating 卡死)](#71-强制删除-api-对象-terminating-卡死)
    - [7.2 物理节点深度清理 (API 删除无效时)](#72-物理节点深度清理-api-删除无效时)
    - [7.3 Ansible 批量清理 (多节点操作)](#73-ansible-批量清理-多节点操作)
  - [8. AscendJob 训练任务专用](#8-ascendjob-训练任务专用)


## 1. 基础配置与环境
管理 kubectl 配置、上下文及 API 资源。

| 命令                                | 说明                               | 示例                                     |
| :---------------------------------- | :--------------------------------- | :--------------------------------------- |
| `kubectl config view`               | 查看当前 kubeconfig 配置           |                                          |
| `kubectl config get-contexts`       | 查看所有上下文                     |                                          |
| `kubectl config use-context <name>` | 切换上下文（集群环境）             | `kubectl config use-context dev-cluster` |
| `kubectl api-resources`             | 列出所有支持的 API 资源类型        | `kubectl api-resources \| grep ascend`   |
| `kubectl explain <resource>`        | 查看资源字段文档 (相当于 man 手册) | `kubectl explain pod.spec.containers`    |

**通用参数 (Global Flags)**:
- `-n <namespace>`: 指定命名空间 (默认 default)。`-A` 或 `--all-namespaces` 表示所有。
- `-o <format>`: 输出格式。`wide` (详细), `yaml` (YAML配置), `json`, `name` (仅名称)。
- `--dry-run=client`: 试运行，不实际提交，常配合 `-o yaml` 生成模板。

---

## 2. 集群与节点管理
查看集群状态、节点资源及调度控制。

| 命令                            | 说明                            | 示例                                        |
| :------------------------------ | :------------------------------ | :------------------------------------------ |
| `kubectl cluster-info`          | 查看控制平面组件状态            |                                             |
| `kubectl get nodes -o wide`     | 查看节点 IP、内核版本、OS 等    |                                             |
| `kubectl top node`              | **实时监控**节点 CPU/内存使用率 |                                             |
| `kubectl describe node <name>`  | 查看节点分配资源、污点、事件    | `kubectl describe node bms1889`             |
| `kubectl label node <name> k=v` | 给节点打标签                    | `kubectl label node bms1905 kuang=120`      |
| `kubectl cordon <node>`         | **禁止调度** (维护模式)         | `kubectl cordon bms1889`                    |
| `kubectl uncordon <node>`       | 恢复调度                        | `kubectl uncordon bms1889`                  |
| `kubectl drain <node>`          | 驱逐节点上的 Pod (维护前清空)   | `kubectl drain bms1889 --ignore-daemonsets` |


### 2.1 给节点打Label 

在 k8s 集群中，给节点打 Label 是一种常见的操作，用于对节点进行分类、标识或分组。使用 `kubectl label node` 命令可以给节点添加标签。下面的脚本提供了批量给节点打 Label 的方法。

```bash
#!/usr/bin/env bash

start="${1:-bms0001}"
end="${2:-bms0448}"
label="${3}"

if [ -z "$label" ]; then
  echo "Usage: $0 <start_node> <end_node> <label>"
  echo "Example: $0 bms0001 bms0448 env=prod"
  exit 1
fi

# Strip 'bms' prefix
start_num="${start#bms}"
end_num="${end#bms}"

echo "Labeling nodes from bms${start_num} to bms${end_num} with ${label}..."

# Generate nodes list with padding (assuming 4 digits like bms0001)
nodes=$(seq -f "bms%04g" "$start_num" "$end_num")

# Apply label using xargs to handle list
echo "$nodes" | xargs kubectl label nodes --overwrite "$label"
```
你需要提供具体的标签键值对（例如 `env=prod`），命令如下：

```bash
# 用法: bash scripts/labeled_nodes.sh <开始节点> <结束节点> <标签键=值>
bash scripts/labeled_nodes.sh bms0001 bms0448 <key>=<value>
```

或者直接使用下面的一行命令（请替换 `<key>=<value>` 为你实际要打的标签）：

```bash
kubectl label nodes $(seq -f "bms%04g" 1 448) <key>=<value> --overwrite
```

**验证标签是否打上：**

```bash
kubectl get nodes bms0001 bms0448 --show-labels
```

### 2.2 标记坏节点并禁止调度

典型场景：节点硬件/NPU/网络等存在问题，希望调度默认避开这些节点。

**方式一：临时停止使用节点（不改 Pod 配置）**

- 仅禁止新 Pod 调度到该节点：
  ```bash
  kubectl cordon <node-name>
  ```

- 禁止调度并驱逐现有 Pod（除 DaemonSet 外）：
  ```bash
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  ```

这种方式适合短期维护或临时下线节点。

**方式二：使用污点标记坏节点（推荐）**

使用 **污点（taint）** 可以在调度层面将节点标记为“坏节点”，普通 Pod 不会再调度上去：

- 只禁止新 Pod 调度到该节点：
  ```bash
  kubectl taint nodes <node-name> node-status=bad:NoSchedule
  ```

- 禁止新 Pod 调度，并驱逐当前不容忍该污点的 Pod：
  ```bash
  kubectl taint nodes <node-name> node-status=bad:NoExecute
  ```

- 恢复节点（移除该 key 的污点）：
  ```bash
  kubectl taint nodes <node-name> node-status-
  ```

对于极少数仍需运行在“坏节点”上的系统 Pod，可在其 Pod 配置中添加容忍：

```yaml
tolerations:
  - key: "node-status"
    operator: "Equal"
    value: "bad"
    effect: "NoSchedule"
  - key: "node-status"
    operator: "Equal"
    value: "bad"
    effect: "NoExecute"
```

**方式三：使用标签 + nodeAffinity 避开坏节点（需统一 YAML 模板）**

仅给节点打标签 **不会**改变调度行为，必须在 Pod 侧通过 `nodeAffinity` 显式避开：

- 给坏节点打标签：
  ```bash
  kubectl label node <node-name> node-status=bad
  ```

- 在 Pod/Deployment 中添加节点亲和性，只调度到 `node-status != bad` 的节点：
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

此方式适用于所有业务 Pod 都通过同一套 YAML/模板管理的场景，否则容易遗漏。

**快速选择建议**

- 应急/短期维护：使用 `kubectl cordon` / `kubectl drain`。
- 集群默认避开坏节点（推荐）：对节点添加污点 taint。
- 有统一 CI/CD 与模板体系：在此基础上再使用标签 + nodeAffinity 做更精细控制。

---

### 2.3 查看所有节点的 Label

要查找 Kubernetes 中所有打过的 Label（标签），主要分两种场景：**查看所有节点的 Label** 和 **统计集群中出现过哪些 Label Key**。

#### 1. 查看所有节点的 Label

这是最常用的命令，会列出每个节点及其所有的 Label：

```bash
kubectl get nodes --show-labels
```

如果 Label 太多导致显示不全，可以用 `json` 或 `yaml` 格式查看：

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels}{"\n"}{end}'
```

#### 2. 统计集群中出现过的所有 Label Key（去重）

如果你想知道“目前集群里到底用过哪些 Label 键名”，可以使用以下命令（需要 `jq`）：

```bash
kubectl get nodes -o json | jq -r '.items[].metadata.labels | keys[]' | sort | uniq
```

如果没有 `jq`，可以用 `grep` 粗略查看：

```bash
kubectl get nodes --show-labels | grep -oP '(?<=,|^)[^=,]+(?==)' | sort | uniq
```

#### 3. 查找打过特定 Label 的节点

如果你是想找“哪些节点打了某个 Label”，可以使用 `-l` 参数：

```bash
# 查找打过 disktype=ssd 的节点
kubectl get nodes -l disktype=ssd

# 查找打过 environment 标签的节点（不管值是什么）
kubectl get nodes -l environment
```

#### 4. 查找 Pod 的 Label

如果你的目标是 Pod 而不是 Node，把上面的 `nodes` 换成 `pods` 即可：

```bash
kubectl get pods --show-labels -A
```

## 3. Pod 与容器管理
最核心的日常操作，涉及 Pod 的增删改查与交互。

| 命令                                          | 说明                                  | 示例                                          |
| :-------------------------------------------- | :------------------------------------ | :-------------------------------------------- |
| `kubectl get pods -A`                         | 查看所有 Pod                          |                                               |
| `kubectl run <name> --image=<img>`            | 快速启动一个 Pod                      | `kubectl run nginx --image=nginx:alpine`      |
| `kubectl logs <pod> [-c <container>]`         | 查看日志 (`-f` 实时, `-p` 上一个实例) | `kubectl logs -f my-pod -c worker`            |
| `kubectl exec -it <pod> -- <cmd>`             | **进入容器**或执行命令                | `kubectl exec -it my-pod -- bash`             |
| `kubectl cp <local> <pod>:<remote>`           | 文件复制 (双向)                       | `kubectl cp ./data.csv my-pod:/data/`         |
| `kubectl port-forward <pod> <local>:<remote>` | 端口转发 (本地访问 Pod 服务)          | `kubectl port-forward redis-master 6379:6379` |
| `kubectl delete pod <name>`                   | 删除 Pod                              | `kubectl delete pod my-pod --grace-period=0`  |

---

## 4. 工作负载 (Deployments/Jobs)
管理应用副本、滚动更新与批处理任务。

| 命令                                       | 说明                  | 示例                                            |
| :----------------------------------------- | :-------------------- | :---------------------------------------------- |
| `kubectl get deploy,sts,ds`                | 查看各类工作负载状态  |                                                 |
| `kubectl scale deploy <name> --replicas=N` | **手动扩缩容**        | `kubectl scale deploy/nginx --replicas=3`       |
| `kubectl rollout status deploy <name>`     | 查看滚动更新进度      |                                                 |
| `kubectl rollout undo deploy <name>`       | **回滚**到上一个版本  |                                                 |
| `kubectl rollout restart deploy <name>`    | 重启所有 Pod (无中断) | `kubectl rollout restart deploy/nginx`          |
| `kubectl create job --from=cronjob/<name>` | 手动触发 CronJob      | `kubectl create job test --from=cronjob/backup` |

---

## 5. 网络与服务
调试 Service (SVC) 和 Ingress。

| 命令                           | 说明                                          | 示例                                                    |
| :----------------------------- | :-------------------------------------------- | :------------------------------------------------------ |
| `kubectl get svc,ep`           | 查看 Service 及对应的 Endpoints (后端 Pod IP) |                                                         |
| `kubectl get ingress`          | 查看 Ingress 路由规则                         |                                                         |
| `kubectl expose deploy <name>` | 快速为 Deployment 创建 Service                | `kubectl expose deploy nginx --port=80 --type=NodePort` |
| `kubectl describe svc <name>`  | 排查 Service 无法连通的问题                   |                                                         |

---

## 6. 配置与存储
管理 ConfigMap, Secret, PVC, PV。

| 命令                            | 说明                                         | 示例                                                          |
| :------------------------------ | :------------------------------------------- | :------------------------------------------------------------ |
| `kubectl get cm,secret`         | 查看配置与密钥                               |                                                               |
| `kubectl create secret generic` | 创建密钥                                     | `kubectl create secret generic db-pass --from-literal=pw=123` |
| `kubectl get pvc,pv`            | 查看持久化卷状态                             |                                                               |
| `kubectl describe pvc <name>`   | 排查 PVC Pending 原因 (如 storageclass 问题) |                                                               |

---

## 7. 故障排查与清理
**高频使用**：处理卡死资源与节点残留。

### 7.1 强制删除 API 对象 (Terminating 卡死)
```bash
# 强制删除单个 Pod (不等待 graceful period)
kubectl delete pod <pod-name> --force --grace-period=0

# 批量强制删除所有 Terminating 状态的 Pod
kubectl get pods | grep Terminating | awk '{print $1}' | xargs kubectl delete pod --force --grace-period=0
```

### 7.2 物理节点深度清理 (API 删除无效时)
**场景**：API 对象已删，但节点上显存未释放或进程残留。

```bash
# 1. 登录物理节点 (kubectl get pods -o wide 获取 IP)
ssh root@<node-ip>

# 2. 清理残留容器 (Docker 环境)
docker ps | grep <keyword> | awk '{print $1}' | xargs docker rm -f

# 3. 清理残留容器 (Containerd/CRI 环境)
crictl ps | grep <keyword> | awk '{print $1}' | xargs crictl rm

# 4. 终极手段：清理占用 NPU 的僵尸进程
# 查找占用 Ascend NPU 设备 (/dev/davinci*) 的进程
fuser -v /dev/davinci*

# 强制杀掉残留的训练进程 (慎用 kill -9)
ps -ef | grep python | grep <task-keyword> | awk '{print $2}' | xargs kill -9
```

### 7.3 Ansible 批量清理 (多节点操作)

适用于多机集群的快速清理，无需逐个登录节点。

```bash
# 批量停止并删除包含特定关键字 (如 llama31) 的容器
# 注意：需替换 inventory 文件名 (host-kuang73-74) 和 过滤关键字 (llama31)
ansible -i host-kuang73-74 all -m shell -a 'bash -c "crictl ps -a | grep llama31 | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'

ansible -i host-train-1024npu all -m shell -a 'bash -c "crictl ps -a | grep llama31 | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'

ansible -i host-train-1024npu all -m shell -a 'bash -c "crictl ps -a | grep deepseek | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'

ansible -i host-train-1024npu all -m shell -a 'bash -c "crictl ps -a | grep kimi | awk \"{print \$1}\" | xargs -I {} crictl stop {} && crictl rm {}"'
```


---

## 8. AscendJob 训练任务专用
Huawei Ascend 910B AI 训练任务 (MindX DL) 核心操作。

| 命令                                                   | 说明                               |
| :----------------------------------------------------- | :--------------------------------- |
| `kubectl apply -f pytorch_singlenodes_acjob_910b.yaml` | 提交单机训练任务                   |
| `kubectl apply -f pytorch_multinodes_acjob_910b.yaml`  | 提交多机训练任务                   |
| `kubectl get ascendjob`                                | 查看任务总览 (状态/运行时长)       |
| `kubectl describe ascendjob <name>`                    | **查看任务事件** (报错/重调度信息) |
| `kubectl delete ascendjob <name>`                      | 删除任务 (自动级联删除 Pods)       |

**AscendJob 标准调试流程：**
1. **提交任务**: `kubectl apply -f <yaml>`
2. **监控启动**: `kubectl get pods -l job-name=<name> -w`
3. **查看日志**:
   - Master 节点: `kubectl logs -f <name>-master-0`
   - Worker 节点: `kubectl logs -f <name>-worker-0`
4. **故障排查**:
   - 如果 Pod Pending: `kubectl describe pod <pod-name>` (看调度失败原因)
   - 如果 Pod Running 但卡住: 进入容器 `kubectl exec -it <pod> -- bash` 查看 `/var/log/npu` 或应用日志。
5. **清理环境**: `kubectl delete ascendjob <name>` (推荐使用 delete -f yaml)
