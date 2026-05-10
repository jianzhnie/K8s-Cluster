# Kubernetes 零基础学习指南

> **适用版本**: Kubernetes v1.25+
> **前置知识**: Linux 命令行基础、Docker 容器概念（镜像/容器）、网络基础（IP/端口）

---

## 目录

1. [学习路径与核心概念](#1-学习路径与核心概念)
2. [Namespace - 资源隔离](#2-namespace---资源隔离)
3. [Pod - 最小调度单元](#3-pod---最小调度单元)
4. [Deployment - 无状态应用管理](#4-deployment---无状态应用管理)
5. [Service - 服务发现与暴露](#5-service---服务发现与暴露)
6. [ConfigMap 与 Secret - 配置管理](#6-configmap-与-secret---配置管理)
7. [学习总结与进阶路线](#7-学习总结与进阶路线)

---

## 1. 学习路径与核心概念

### 什么是 Kubernetes

Kubernetes (K8s) 是一个开源的容器编排引擎，用于自动化部署、扩展和管理容器化应用程序。

### 架构概览

```
┌──────────────────────── Master (控制平面) ────────────────────────┐
│  API Server  ←── kubectl / 用户请求                                │
│  Scheduler    → 决定 Pod 运行在哪个 Node                           │
│  Controller   → 监控并维持期望状态 (如副本数)                       │
│  etcd         → 存储集群所有数据的键值数据库                        │
└───────────────────────────────────────────────────────────────────┘
         │
         │ 下发调度指令
         ▼
┌──────────────── Node (工作节点) ──────────────────┐
│  kubelet       → 管理 Pod 生命周期                │
│  kube-proxy    → 维护网络规则和 Service 转发      │
│  Container Runtime → 运行容器 (Docker/containerd) │
└───────────────────────────────────────────────────┘
```

- **Master 节点**：集群的大脑，负责调度、决策和状态存储。
- **Node 节点**：工作节点，负责实际运行容器。

### 学习路径

本指南遵循 **由浅入深** 的顺序：

```
Namespace → Pod → Deployment → Service → ConfigMap/Secret
   (隔离)    (最小单元)  (副本管理)   (服务发现)    (配置解耦)
```

掌握以上核心对象后，可继续学习 [K8s 配置与 Ascend 训练全指南](k8s-cluster-guide.md) 和 [K8s 命令速查手册](k8s-commands-cheatsheet.md)。

### 集群状态查看

```bash
# 查看集群信息
kubectl cluster-info

# 查看节点状态
kubectl get nodes -o wide
```

---

## 2. Namespace - 资源隔离

### 概念

Namespace 提供虚拟的隔离环境，将集群资源划分到不同空间中，实现多租户隔离。

**使用场景**：区分开发 (`dev`)、测试 (`test`)、生产 (`prod`) 环境；多团队共享集群。

### 实战

**YAML 配置** (`namespace-demo.yaml`):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: study-k8s
```

```bash
# 创建（两种方式任选）
kubectl apply -f namespace-demo.yaml
kubectl create namespace study-k8s

# 查询
kubectl get ns

# 删除
kubectl delete ns study-k8s
```

> **提示**：删除 Namespace 会级联删除其下所有资源，生产环境慎用。

### 练习

1. 创建一个名为 `practice` 的 Namespace。
2. 查询该 Namespace 下的 Pod（应为空）。

---

## 3. Pod - 最小调度单元

### 概念

Pod 是 Kubernetes 中可以创建和管理的 **最小部署单元**。一个 Pod 包含一个或多个容器（通常是一个），它们共享存储和网络。

### 核心命令

| 命令                           | 说明                     | 示例                            |
| :----------------------------- | :----------------------- | :------------------------------ |
| `kubectl get pods [-n <ns>]`   | 查看 Pod 列表            | `kubectl get pods -n study-k8s` |
| `kubectl describe pod <name>`  | 查看详细事件和状态（排错）| `kubectl describe pod my-nginx` |
| `kubectl logs <name> [-f]`     | 查看日志，`-f` 实时跟踪  | `kubectl logs -f my-nginx`      |
| `kubectl exec -it <pod> -- sh` | 进入容器终端             | `kubectl exec -it my-nginx -- bash` |

### 实战：运行一个 Nginx Pod

**YAML 配置** (`pod-demo.yaml`):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-nginx
  namespace: study-k8s
  labels:
    app: nginx-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.21
    ports:
    - containerPort: 80
```

```bash
# 前置：确保命名空间存在
kubectl create ns study-k8s

# 创建
kubectl apply -f pod-demo.yaml

# 验证（状态 ContainerCreating → Running）
kubectl get pods -n study-k8s

# 清理
kubectl delete -f pod-demo.yaml
```

### 常见错误

| 状态                  | 原因           | 排查方法                                       |
| :-------------------- | :------------- | :--------------------------------------------- |
| **ErrImagePull**      | 镜像拉取失败   | 检查 `image` 名称和网络连接                    |
| **CrashLoopBackOff**  | 容器启动后退出 | `kubectl logs <pod>` 查看应用日志              |
| **Pending**           | 无法调度       | `kubectl describe pod <pod>` 查看调度失败原因  |

### YAML 结构解析

```yaml
apiVersion: v1          # API 版本
kind: Pod               # 资源类型
metadata:               # 元数据
  name: my-nginx        #   Pod 名称（同一 Namespace 内唯一）
  labels:               #   标签（用于 Service/Deployment 筛选）
    app: nginx-demo
spec:                   # 期望状态
  containers:           #   容器列表
  - name: nginx         #     容器名
    image: nginx:1.21   #     镜像
    ports:
    - containerPort: 80 #     容器端口
```

> **关键理解**：K8s 中所有配置都遵循 `apiVersion` → `kind` → `metadata` → `spec` 这个四层结构。

---

## 4. Deployment - 无状态应用管理

### 概念

直接管理 Pod 有个致命问题：Pod 死了不会自动恢复。**Deployment** 是一个控制器，它确保指定数量的 Pod 副本始终运行，并支持滚动更新和回滚。

```
Deployment → 管理 ReplicaSet → 管理 Pod
```

- **ReplicaSet**：确保指定数量的 Pod 副本在运行（由 Deployment 自动管理，通常不需要直接操作）。
- **滚动更新**：更新镜像时逐步替换旧 Pod，不中断服务。

### 实战：部署 3 副本 Nginx

**YAML 配置** (`deployment-demo.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  namespace: study-k8s
spec:
  replicas: 3                # 期望 3 个副本
  selector:
    matchLabels:
      app: nginx-app         # 必须匹配 template 中的 label
  template:                  # Pod 模板
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

```bash
# 创建
kubectl apply -f deployment-demo.yaml

# 验证（READY 3/3 表示全部就绪）
kubectl get deploy -n study-k8s

# 查看 Deployment 自动创建的 Pod
kubectl get pods -n study-k8s -l app=nginx-app

# 扩容到 5 个副本
kubectl scale deployment nginx-deploy --replicas=5 -n study-k8s

# 滚动更新镜像
kubectl set image deployment/nginx-deploy nginx=nginx:1.22 -n study-k8s
kubectl rollout status deployment/nginx-deploy -n study-k8s

# 回滚到上一个版本
kubectl rollout undo deployment/nginx-deploy -n study-k8s

# 清理
kubectl delete -f deployment-demo.yaml
```

### 练习

1. 将副本数缩减为 1，观察变化。
2. 手动删除其中一个 Pod，观察 Deployment 是否自动重建（自愈能力）。
3. 更新镜像到 `nginx:1.22`，然后回滚到 `nginx:1.21`。

---

## 5. Service - 服务发现与暴露

### 概念

Pod 的 IP 是动态的，每次重建都会变化。**Service** 为一组 Pod 提供固定的访问入口（ClusterIP + DNS 名称），并通过 Label Selector 自动关联后端 Pod。

```
客户端 → Service (固定 IP/DNS) → Pod (动态 IP)
                ↑
          Label Selector 匹配
```

### Service 类型

| 类型           | 说明                             | 适用场景             |
| :------------- | :------------------------------- | :------------------- |
| `ClusterIP`    | 仅集群内可访问（默认）           | 内部服务间调用       |
| `NodePort`     | 在节点开放端口 (30000-32767)     | 临时调试、外部访问   |
| `LoadBalancer` | 对接云厂商负载均衡器             | 生产环境对外暴露     |

### 实战：暴露 Nginx Deployment

**YAML 配置** (`service-demo.yaml`):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: study-k8s
spec:
  selector:
    app: nginx-app          # 关联 Deployment 中 Pod 的 label
  type: NodePort
  ports:
  - protocol: TCP
    port: 80                # Service 端口
    targetPort: 80          # Pod 容器端口
    nodePort: 30080         # 节点端口 (可选, 范围 30000-32767)
```

```bash
# 创建
kubectl apply -f service-demo.yaml

# 验证
kubectl get svc -n study-k8s
# NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# nginx-service   NodePort   10.96.123.45    <none>        80:30080/TCP   10s

# 访问测试（在集群节点上执行）
curl http://localhost:30080

# 清理
kubectl delete -f service-demo.yaml
```

### 关键理解：Label 与 Selector 的协作

```
Deployment (labels: app=nginx-app)
    ↓ 创建 Pod
Pod (labels: app=nginx-app)
    ↓ selector 匹配
Service (selector: app=nginx-app) → 将流量转发到匹配的 Pod
```

Label 是 K8s 中最核心的关联机制。所有资源之间的关系几乎都通过 Label + Selector 建立。

---

## 6. ConfigMap 与 Secret - 配置管理

### 概念

将配置从镜像中解耦出来，避免每次修改配置都要重新构建镜像。

- **ConfigMap**：存储非敏感配置（配置文件、环境变量）。
- **Secret**：存储敏感信息（密码、证书、Token），Base64 编码存储。

### 实战：为 Nginx 注入配置

**ConfigMap** (`configmap-demo.yaml`):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: study-k8s
data:
  INDEX_HTML: |
    <h1>Hello from ConfigMap!</h1>
```

**在 Pod 中使用**：

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.21
    envFrom:                    # 方式一：环境变量注入
    - configMapRef:
        name: nginx-config
    # volumeMounts:             # 方式二：文件挂载（支持热更新）
    # - name: config
    #   mountPath: /etc/nginx/conf.d
  # volumes:
  # - name: config
  #   configMap:
  #     name: nginx-config
```

| 挂载方式     | 特点                   | 适用场景               |
| :----------- | :--------------------- | :--------------------- |
| `envFrom`    | 简单直接，但修改需重启 | 少量变量、启动时确定   |
| Volume 挂载  | 支持热更新             | 配置文件、需要动态更新 |

---

## 7. 学习总结与进阶路线

### 核心对象关系图

```
┌─────────────────────────────────────────────────┐
│  Namespace (隔离空间)                            │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  Deployment (管理副本数和更新策略)         │   │
│  │    selector: app=nginx                    │   │
│  │    ┌────────┐ ┌────────┐ ┌────────┐      │   │
│  │    │  Pod   │ │  Pod   │ │  Pod   │      │   │
│  │    │ labels:│ │ labels:│ │ labels:│      │   │
│  │    │app=    │ │app=    │ │app=    │      │   │
│  │    │nginx   │ │nginx   │ │nginx   │      │   │
│  │    └────────┘ └────────┘ └────────┘      │   │
│  │         ↑ selector 匹配                   │   │
│  │  Service (固定访问入口)                    │   │
│  │  ConfigMap / Secret (配置注入)             │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### 术语速查

| 术语                | 含义                                                       |
| :------------------ | :--------------------------------------------------------- |
| **Cluster**         | 集群，计算资源的集合。                                     |
| **Master/Node**     | 控制平面（调度/决策）/ 工作节点（运行容器）。              |
| **Pod**             | 最小调度单元，包含一个或多个共享网络的容器。               |
| **Deployment**      | 管理 Pod 副本数和更新策略的控制器。                        |
| **ReplicaSet**      | 确保指定数量的 Pod 副本运行（由 Deployment 自动管理）。    |
| **Service**         | 为一组 Pod 提供固定访问入口（IP + DNS）。                 |
| **Namespace**       | 资源隔离空间。                                             |
| **Label / Selector**| 键值对标签及选择器，K8s 中资源关联的核心机制。             |
| **ConfigMap**       | 非敏感配置存储。                                           |
| **Secret**          | 敏感信息存储。                                             |
| **YAML**            | K8s 资源的声明式配置格式。                                 |

### 进阶路线

完成本指南后，推荐按以下顺序继续学习：

| 阶段 | 主题 | 参考 |
| :--- | :--- | :--- |
| 命令掌握 | kubectl 命令速查 | [k8s-commands-cheatsheet.md](k8s-commands-cheatsheet.md) |
| 配置详解 | YAML 配置、Ingress、RBAC、HPA | [k8s-cluster-guide.md](k8s-cluster-guide.md) |
| AI 训练 | Ascend 910B NPU 训练 (AscendJob) | [k8s-cluster-guide.md](k8s-cluster-guide.md) 第二部分 |
