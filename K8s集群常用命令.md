# K8s 集群常用命令速查手册 (V2.0)

本手册汇集了 Kubernetes 集群日常运维、开发调试及故障处理的常用命令。

## 目录
- [K8s 集群常用命令速查手册 (V2.0)](#k8s-集群常用命令速查手册-v20)
  - [目录](#目录)
  - [1. 基础配置与环境](#1-基础配置与环境)
  - [2. 集群与节点管理](#2-集群与节点管理)
  - [3. Pod 与容器管理](#3-pod-与容器管理)
  - [4. 工作负载 (Deployments/Jobs)](#4-工作负载-deploymentsjobs)
  - [5. 网络与服务](#5-网络与服务)
  - [6. 配置与存储](#6-配置与存储)
  - [7. 故障排查与清理](#7-故障排查与清理)
    - [7.1 强制删除 API 对象 (Terminating 卡死)](#71-强制删除-api-对象-terminating-卡死)
    - [7.2 物理节点深度清理 (API 删除无效时)](#72-物理节点深度清理-api-删除无效时)
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
