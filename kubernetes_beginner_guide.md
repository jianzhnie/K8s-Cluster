# Kubernetes (K8S) 初学者零基础学习指南

## 目录 (Table of Contents)

1. [前言与学习路径](#1-前言与学习路径)
2. [第一章：环境准备与基础概念](#2-第一章环境准备与基础概念)
3. [第二章：命名空间 (Namespace)](#3-第二章命名空间-namespace)
4. [第三章：Pod - K8S 的最小原子](#4-第三章pod---k8s-的最小原子)
5. [第四章：Deployment - 无状态应用管理](#5-第四章deployment---无状态应用管理)
6. [第五章：Service - 服务发现与网络暴露](#6-第五章service---服务发现与网络暴露)
7. [kubectl 命令速查手册](#7-kubectl-命令速查手册)
8. [术语表与快速索引](#8-术语表与快速索引)

---

## 1. 前言与学习路径

### 学习路径设计
本指南遵循 **由浅入深** 的原则，建议按照以下顺序学习：

1. **基础认知**：理解 K8S 是什么，架构组件（Master/Node）。
2. **核心对象**：Namespace -> Pod -> Deployment -> Service。
3. **进阶配置**：ConfigMap/Secret, Volume, Ingress (本指南主要覆盖前两阶段)。

### 前置知识要求
- 基本的 Linux 命令行操作。
- 了解 Docker 容器基础（镜像、容器概念）。
- 网络基础（IP、端口）。

---

## 2. 第一章：环境准备与基础概念

### 概念解释
Kubernetes 是一个开源的容器编排引擎，用于自动化部署、扩展和管理容器化应用程序。

- **Master 节点**：集群的大脑，负责调度和管理。
- **Node 节点**：工作节点，负责运行容器。

### 常用命令分类：集群管理 (Cluster Management)

| 命令           | 语法格式               | 说明         | 示例                   |
| -------------- | ---------------------- | ------------ | ---------------------- |
| `cluster-info` | `kubectl cluster-info` | 查看集群信息 | `kubectl cluster-info` |
| `get nodes`    | `kubectl get nodes`    | 查看节点状态 | `kubectl get nodes`    |

---

## 3. 第二章：命名空间 (Namespace)

### 概念解释
Namespace 提供了虚拟的隔离环境。通过将集群资源划分到不同的 Namespace 中，可以实现多租户隔离（如开发环境 `dev`、测试环境 `test`）。

### 使用场景
- 多团队共享集群。
- 区分开发、测试、生产环境。

### 实战示例

#### 1. YAML 配置文件 (`namespace-demo.yaml`)
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: study-k8s
```

#### 2. 操作步骤

**创建 (Create)**
```bash
kubectl apply -f namespace-demo.yaml
# 输出: namespace/study-k8s created
```
或者使用命令直接创建：
```bash
kubectl create namespace study-k8s
```

**查询 (Query)**
```bash
kubectl get ns
# 输出: 
# NAME              STATUS   AGE
# default           Active   10d
# study-k8s         Active   5s
```

**清理 (Clean)**
```bash
kubectl delete -f namespace-demo.yaml
# 或者
kubectl delete ns study-k8s
```

### 练习任务
- 创建一个名为 `practice` 的 namespace。
- 尝试查询该 namespace 下的资源（目前应为空）。

---

## 4. 第三章：Pod - K8S 的最小原子

### 概念解释
Pod 是 Kubernetes 中可以创建和管理的最小部署单元。一个 Pod 可以包含一个或多个容器（通常是一个），它们共享存储和网络。

### 使用场景
- 运行一个简单的应用实例。
- 紧密耦合的辅助容器（Sidecar 模式）。

### 相关命令：资源查询与调试

| 命令       | 语法                          | 参数说明                                           | 示例                             |
| ---------- | ----------------------------- | -------------------------------------------------- | -------------------------------- |
| `get pods` | `kubectl get pods [flags]`    | `-n <ns>`: 指定命名空间<br>`-o wide`: 显示IP和节点 | `kubectl get pods -n study-k8s`  |
| `describe` | `kubectl describe pod <name>` | 查看详细事件和状态                                 | `kubectl describe pod nginx-pod` |
| `logs`     | `kubectl logs <name>`         | `-f`: 实时跟踪                                     | `kubectl logs -f nginx-pod`      |

### 实战示例：运行一个 Nginx Pod

#### 1. YAML 配置文件 (`pod-demo.yaml`)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-nginx
  namespace: study-k8s  # 指定我们刚才创建的 namespace，如果已删除请先重建
  labels:
    app: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.21
    ports:
    - containerPort: 80
```

#### 2. 操作步骤

**前置准备**
确保 `study-k8s` 命名空间存在：
```bash
kubectl create ns study-k8s
```

**创建**
```bash
kubectl apply -f pod-demo.yaml
# 输出: pod/my-nginx created
```

**验证**
```bash
kubectl get pods -n study-k8s
# 此时状态可能为 ContainerCreating -> Running
```
查看详细信息（用于排错）：
```bash
kubectl describe pod my-nginx -n study-k8s
```

**常见错误与解决**
- **ErrImagePull / ImagePullBackOff**: 镜像拉取失败。
  - *解决*: 检查 `image` 名称拼写，检查网络连接。
- **CrashLoopBackOff**: 容器启动后立即退出。
  - *解决*: 使用 `kubectl logs my-nginx -n study-k8s` 查看应用日志。

**清理**
```bash
kubectl delete -f pod-demo.yaml
```

---

## 5. 第四章：Deployment - 无状态应用管理

### 概念解释
直接管理 Pod 很麻烦（Pod 死了不会自动复活）。Deployment 是一种控制器，它管理 Pod 的副本数量（Replicas）、版本更新和回滚。它是最常用的工作负载资源。

### 使用场景
- 部署无状态应用（Web 服务、API）。
- 应用扩缩容。
- 滚动更新（不中断服务更新镜像）。

### 实战示例：部署 3 个副本的 Nginx

#### 1. YAML 配置文件 (`deployment-demo.yaml`)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  namespace: study-k8s
spec:
  replicas: 3               # 期望 3 个副本
  selector:
    matchLabels:
      app: nginx-app        # 必须匹配 template 中的 label
  template:                 # Pod 模板
    metadata:
      labels:
        app: nginx-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
```

#### 2. 操作步骤

**创建**
```bash
kubectl apply -f deployment-demo.yaml
```

**验证扩缩容**
```bash
kubectl get deploy -n study-k8s
# 输出 READY 3/3

# 查看自动创建的 Pods
kubectl get pods -n study-k8s -l app=nginx-app
```

**命令式扩容 (Scaling)**
```bash
kubectl scale deployment nginx-deploy --replicas=5 -n study-k8s
# 再次查看 Pods，会发现变成了 5 个
```

**更新镜像 (Rolling Update)**
```bash
kubectl set image deployment/nginx-deploy nginx=nginx:1.22 -n study-k8s
# 观察滚动更新过程
kubectl rollout status deployment/nginx-deploy -n study-k8s
```

### 练习任务
- 将副本数缩减为 1。
- 尝试删除其中一个 Pod，观察 Deployment 是否会自动重建一个新的 Pod（自愈能力）。

---

## 6. 第五章：Service - 服务发现与网络暴露

### 概念解释
Pod 的 IP 是动态的，重启后会变。Service 定义了一组 Pod 的逻辑集合和访问策略，提供一个固定的 VIP (ClusterIP) 和 DNS 名称。

### 使用场景
- **ClusterIP** (默认): 集群内部服务间调用。
- **NodePort**: 将服务暴露到节点端口，供外部访问。
- **LoadBalancer**: 云厂商提供的负载均衡器。

### 实战示例：暴露 Nginx Deployment

#### 1. YAML 配置文件 (`service-demo.yaml`)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: study-k8s
spec:
  selector:
    app: nginx-app      # 关联 Deployment 中定义的 label
  type: NodePort        # 暴露类型
  ports:
  - protocol: TCP
    port: 80            # Service 端口
    targetPort: 80      # Pod 容器端口
    nodePort: 30080     # (可选) 固定节点端口，范围 30000-32767
```

#### 2. 操作步骤

**创建**
```bash
kubectl apply -f service-demo.yaml
```

**验证**
```bash
kubectl get svc -n study-k8s
# 输出示例:
# NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# nginx-service   NodePort   10.96.123.45    <none>        80:30080/TCP   10s
```

**访问测试**
在集群节点上访问：
```bash
curl http://localhost:30080
# 应该能看到 Nginx 欢迎页面
```

---

## 7. kubectl 命令速查手册

### 资源创建类 (Create/Update)

| 命令                | 常用/高级 | 描述                                 | 示例                           |
| ------------------- | --------- | ------------------------------------ | ------------------------------ |
| `apply -f <file>`   | **常用**  | 声明式创建或更新资源                 | `kubectl apply -f deploy.yaml` |
| `create <resource>` | 常用      | 命令式创建资源                       | `kubectl create ns test`       |
| `replace -f <file>` | 高级      | 替换现有资源（不推荐，建议用 apply） | `kubectl replace -f pod.yaml`  |

### 资源查询类 (Get/Describe)

| 命令                    | 常用/高级 | 描述                   | 示例                                 |
| ----------------------- | --------- | ---------------------- | ------------------------------------ |
| `get <resource>`        | **常用**  | 列出资源               | `kubectl get pods -A` (所有命名空间) |
| `describe <res> <name>` | **常用**  | 查看详细详情和事件     | `kubectl describe node node-1`       |
| `api-resources`         | 高级      | 列出所有支持的资源类型 | `kubectl api-resources`              |

### 调试排错类 (Debug)

| 命令                     | 常用/高级 | 描述               | 示例                                   |
| ------------------------ | --------- | ------------------ | -------------------------------------- |
| `logs <pod>`             | **常用**  | 查看容器日志       | `kubectl logs my-pod -c my-container`  |
| `exec -it <pod> -- sh`   | **常用**  | 进入容器终端       | `kubectl exec -it my-pod -- /bin/bash` |
| `cp <file> <pod>:<path>` | 高级      | 容器与本地文件复制 | `kubectl cp ./log.txt my-pod:/tmp/`    |

### 维护与删除类 (Delete/Maintain)

| 命令                  | 常用/高级 | 描述                       | 示例                            |
| --------------------- | --------- | -------------------------- | ------------------------------- |
| `delete <res> <name>` | **常用**  | 删除资源                   | `kubectl delete pod my-pod`     |
| `delete -f <file>`    | **常用**  | 根据文件删除资源           | `kubectl delete -f deploy.yaml` |
| `cordon <node>`       | 高级      | 标记节点不可调度（维护用） | `kubectl cordon k8s-node-1`     |

---

## 8. 术语表与快速索引

- **Cluster**: 集群，计算资源的集合。
- **Master/Control Plane**: 控制平面，负责管理集群。
- **Node/Worker**: 工作节点，运行应用负载。
- **Image**: 容器镜像，应用的静态文件包。
- **Container**: 容器，镜像的运行实例。
- **Pod**: K8S 最小调度单元，包含一个或多个容器。
- **ReplicaSet**: 确保指定数量的 Pod 副本在运行。
- **Deployment**: 管理 ReplicaSet 和 Pod 的声明式更新。
- **Service**: 定义一组 Pod 的访问策略。
- **Label**: 键值对标签，用于组织和选择资源。
- **Selector**: 标签选择器，用于查找具有特定 Label 的资源。
- **YAML**: Yet Another Markup Language，K8S 资源的配置格式。

---
*祝你的 K8S 学习之旅愉快！*
