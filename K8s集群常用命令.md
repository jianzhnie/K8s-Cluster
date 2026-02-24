# K8s 集群常用命令速查手册 (V2.0)

本手册汇集了 Kubernetes 集群日常运维、开发调试及故障处理的常用命令。

## 目录
- [K8s 集群常用命令速查手册 (V2.0)](#k8s-集群常用命令速查手册-v20)
  - [目录](#目录)
  - [1. 基础配置与环境](#1-基础配置与环境)
  - [2. 集群与节点管理](#2-集群与节点管理)
    - [标记坏节点并禁止调度](#标记坏节点并禁止调度)
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

### 标记坏节点并禁止调度

典型需求：某些节点硬件或环境有问题，希望调度时自动避开。

**1. 最简单：直接停止在该节点上调度（不改 Pod 配置）**

- 只禁止新 Pod 调度到该节点：
  ```bash
  kubectl cordon <node-name>
  ```
  之后调度器不会再把新 Pod 放到这个节点上，但现有 Pod 还会继续跑。

- 禁止调度 + 迁走现有 Pod：
  ```bash
  kubectl drain <node-name> \
    --ignore-daemonsets \
    --delete-emptydir-data
  ```
  这会把除 DaemonSet 以外的 Pod 都驱逐到其他节点，并且将节点标记为不可调度（内部等价于 cordon）。

这种方式不需要改 Pod 的 YAML，适合“节点坏了先不用”的场景。

**2. 更“语义化”的方式：给节点打标签 + 污点（推荐）**

仅仅“打标签”本身**不会**阻止调度器调度过去，除非你在 Pod 里用 `nodeSelector`/`nodeAffinity` 去“避开”这些标签；这需要改所有工作负载的配置，比较麻烦。

更推荐用 **污点（taint）** 标记坏节点，这样调度器就不会再把普通 Pod 调度过去：

- 给节点加一个“坏节点”的污点，只禁止新 Pod 调度：
  ```bash
  kubectl taint nodes <node-name> node-status=bad:NoSchedule
  ```

- 如果既想阻止新 Pod，又想把现有 Pod 也赶走（类似 drain 效果）：
  ```bash
  kubectl taint nodes <node-name> node-status=bad:NoExecute
  ```
  或者同时：
  ```bash
  kubectl taint nodes <node-name> node-status=bad:NoSchedule,node-status=bad:NoExecute
  ```

- 之后，如果有极少数“特殊 Pod”（比如监控、日志采集）仍然需要落到这些坏节点上，可以在 Pod 里加 **tolerations** 来容忍这个污点，例如：
  ```yaml
  tolerations:
    - key: "node-status"
      operator: "Equal"
      value: "bad"
      effect: "NoSchedule"
  ```

- 想恢复节点时，去掉污点即可：
  ```bash
  kubectl taint nodes <node-name> node-status-
  ```


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


**3. 如果你坚持用“标签”来区分坏节点**

这种方式需要你在所有业务 Pod 的调度策略里“显式避开”坏节点：

- 给坏节点打标签：
  ```bash
  kubectl label nodes <node-name> node-status=bad
  ```

- 在 Pod/Deployment 里用 `nodeAffinity` 避开它们，例如只允许调度到 `node-status != bad` 的节点：
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

但这需要你所有工作负载都遵守这个约束，否则仍然可能调度到坏节点。所以**集群层面一般用 taint 更合适**。


**总结建议**

- 想快速停用某个节点：用 `kubectl cordon` / `kubectl drain`。
- 想长期标记“坏节点”，让调度器默认避开：对该节点加 **污点 taint**，如
  `kubectl taint nodes <node> node-status=bad:NoSchedule`。
- 只有当你有统一的 Pod 模板和 CI/CD，可以批量改 Pod 的 affinity 时，才考虑用**标签 + nodeAffinity** 方案。

---

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
