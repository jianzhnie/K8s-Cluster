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
- [4. 工作负载 (Deployments/Jobs)](#4-工作负载-deploymentsjobs)
- [5. 网络与服务](#5-网络与服务)
- [6. 配置与存储](#6-配置与存储)
- [7. 故障排查与清理](#7-故障排查与清理)
  - [7.1 强制删除卡死资源](#71-强制删除卡死资源)
  - [7.2 物理节点深度清理](#72-物理节点深度清理)
  - [7.3 Ansible 批量清理](#73-ansible-批量清理)
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
# 方式一（推荐，不依赖列宽对齐）
kubectl get node -o name | cut -d/ -f2

# 方式二
kubectl get node --no-headers -o custom-columns=NAME:.metadata.name

# 方式三
kubectl get node --no-headers | awk '{print $1}'
```

### 2.2 Label 标签管理

**单节点操作：**

```bash
# 打标签
kubectl label node <node-name> <key>=<value>
kubectl label node bms1905 kuang=120

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
kubectl get nodes bms0001 bms0448 --show-labels

# 查找打过特定 Label 的节点
kubectl get nodes -l disktype=ssd

# 查找打过某个 key 的节点（不限值）
kubectl get nodes -l environment

# 查找**不带**某个 Label 的节点
kubectl get nodes -l '!environment'

# 排除特定值（key 存在但值不等于）
kubectl get nodes -l 'environment!=somevalue'
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

**单节点操作：**

```bash
# 添加污点（仅禁止新 Pod 调度）
kubectl taint nodes <node-name> node-status=bad:NoSchedule

# 添加污点（禁止调度 + 驱逐不容忍的 Pod）
kubectl taint nodes <node-name> node-status=bad:NoExecute

# 移除污点（key 后加 `-`）
kubectl taint nodes <node-name> node-status-
```

**批量打污点：**

```bash
# 按节点名范围
kubectl taint nodes $(seq -f "bms%04g" 385 448) node-status=bad:NoSchedule --overwrite

# 移除批量污点
kubectl taint nodes $(seq -f "bms%04g" 385 448) node-status-
```

**让特定 Pod 容忍污点（在 Pod YAML 中添加）：**

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
# 给坏节点打标签
kubectl label node <node-name> node-status=bad
```

```yaml
# 在 Pod/Deployment 中添加亲和性，避开坏节点
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
# 指定命名空间，按 Pod 名前缀筛选
kubectl get pod -n <ns> \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
  | grep '^<job-name-prefix>' | awk '{print $2}' | sort -u

# 全局搜索，输出 NS / Pod / Node 对应关系
kubectl get pod -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
  | awk '$2 ~ /<job-name-prefix>/ {print $1,$2,$3}'
```

**实用组合 — 筛选"打了标签但没有运行特定 Pod"的节点：**

```bash
comm -23 \
  <(kubectl get nodes -l <label-key> -o custom-columns=NAME:.metadata.name --no-headers | sort -u) \
  <(kubectl get pod -A -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
    | awk '$1 ~ /^<job-name-prefix>/ {print $2}' | sort -u)
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

---

## 5. 网络与服务

调试 Service 和 Ingress。

| 命令                           | 说明                                          | 示例                                                    |
| :----------------------------- | :-------------------------------------------- | :------------------------------------------------------ |
| `kubectl get svc,ep`           | 查看 Service 及对应的 Endpoints（后端 Pod IP） |                                                         |
| `kubectl get ingress`          | 查看 Ingress 路由规则                         |                                                         |
| `kubectl expose deploy <name>` | 快速为 Deployment 创建 Service                | `kubectl expose deploy nginx --port=80 --type=NodePort` |
| `kubectl describe svc <name>`  | 排查 Service 无法连通的问题                   |                                                         |

---

## 6. 配置与存储

管理 ConfigMap、Secret、PVC、PV。

| 命令                            | 说明                                          | 示例                                                          |
| :------------------------------ | :-------------------------------------------- | :------------------------------------------------------------ |
| `kubectl get cm,secret`         | 查看配置与密钥                                |                                                               |
| `kubectl create secret generic` | 创建密钥                                      | `kubectl create secret generic db-pass --from-literal=pw=123` |
| `kubectl get pvc,pv`            | 查看持久化卷状态                              |                                                               |
| `kubectl describe pvc <name>`   | 排查 PVC Pending 原因（如 storageclass 问题） |                                                               |

---

## 7. 故障排查与清理

### 7.1 强制删除卡死资源

```bash
# 强制删除单个 Pod（跳过优雅退出期）
kubectl delete pod <pod-name> --force --grace-period=0

# 批量删除所有 Terminating 状态的 Pod
kubectl get pods | grep Terminating \
  | awk '{print $1}' | xargs kubectl delete pod --force --grace-period=0
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
# 批量停止并删除包含特定关键字的容器
# 用法：替换 -i 指定的 inventory 文件名和 grep 过滤关键字
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
