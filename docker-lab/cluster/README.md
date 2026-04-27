# Ascend 910C + CANN 8.5.1 + Torch 2.9.0 + vLLM 0.18.0 环境部署指南

本仓库提供一套针对 **昇腾 Atlas 910C**（NPU）的一键化部署脚本，用于快速搭建支持 vLLM 的推理环境。

## 环境说明

- **硬件**：Ascend 910C（一张物理卡对应两个逻辑芯片）
- **软件栈**：
  - CANN 8.5.1
  - PyTorch 2.9.0（torch-npu 适配版）
  - vLLM 0.18.0（Ascend 适配版）
- **部署方式**：离线 Docker 容器（通过 tar.gz 导入镜像）

> **注意**：由于一张物理卡有两个逻辑芯片，启动容器时卡号参数范围为 **0~3**（仅使用物理卡序号，推荐使用 `0`、`1`、`2`、`3`）。

## 前置要求

- 操作系统：Ubuntu / openEuler 等支持 Docker 的 Linux 发行版
- 昇腾驱动与固件已预安装
- 具备 root 或 sudo 权限
- 已准备好以下文件（放在项目根目录）：
  - `install.sh`（Docker 安装脚本）
  - `load_image.sh`（镜像导入脚本，自动删除旧镜像并导入新镜像）
  - `run_container.sh`（容器启动脚本）
  - `docker-27.3.1.tgz` （docker离线安装包）
  - `ascend910c-cann8.5.1-torch2.9.0-vllm0.18.0.tar.gz`（离线 Docker 镜像包）

## 安装和启动步骤

在项目目录下执行以下命令（推荐使用 root 或具有 sudo 权限的用户）：

```bash
# ==================== 步骤 1：检查并处理 Docker ====================

if ! command -v docker &> /dev/null; then
    echo "未检测到 Docker，正在安装 Docker..."
    sudo bash install.sh
else
    echo "Docker 已安装。"
fi

# 检查当前用户是否在 docker 组
if ! groups | grep -q docker; then
    echo "当前用户不在 docker 组中，正在添加用户到 docker 组..."
    sudo usermod -aG docker $USER
    echo "用户已加入 docker 组，请执行以下命令刷新组权限（重要！）："
    echo "    newgrp docker"
    echo "执行 newgrp docker 后，请重新运行此脚本。"
    exit 0
else
    echo "当前用户已在 docker 组中。"
fi

# ==================== 步骤 2：导入 Docker 镜像 ====================

echo "正在导入 Ascend 910C vLLM 镜像（首次导入耗时较长，请耐心等待）..."
bash load_image.sh

# ==================== 步骤 3：启动容器 ====================

echo "正在启动容器，使用物理卡 0 ..."
bash run_container.sh 0
```

## NPUSlim 插件

NPUSlim 以源码形式分发，容器启动时自动 `pip install -e`（editable 模式）。代码更新只需同步源码，无需重启容器。

```bash
# 同步 npuslim 源码到所有机器
bash sync_dist.sh --with-npuslim

# 启动容器时挂载并自动安装
bash run_container.sh 0 --npuslim

# 指定自定义源码路径
bash run_container.sh 0 --npuslim=/path/to/npuslim
```

更新流程：本地修改代码 → `sync_dist.sh --with-npuslim`（同步源码） → 容器内即时生效，无需重启。

## 容器测试
启动容器后，执行以下命令检查npu和torch是否正确：
```bash
# 查看 NPU 状态
npu-smi info

# 测试 vLLM 是否可用
python -c "import torch; a=torch.randn(2,2).npu(); b=torch.randn(2,2).npu(); c=torch.mm(a,b); print(c)"

```

## 多机分布式部署

### 前提条件

1. 所有节点在**同一局域网**，网络互通
2. 所有节点**导入相同镜像**
3. 所有 NPU 通过光模块连接，链路状态正常

### 步骤 1: 在所有节点启动容器

```bash
bash run_container.sh --multi-node
```

### 步骤 2: 验证 NPU 网络 (可选但推荐)

```bash
# 检查链路状态 (应全部为 UP)
for i in {0..7}; do hccn_tool -i $i -link -g; done

# 获取 NPU IP 地址
for i in {0..7}; do hccn_tool -i $i -ip -g | grep ipaddr; done

# 跨节点 PING 测试
hccn_tool -i 0 -ping -g address <目标NPU_IP>
```

### 步骤 3: 启动推理服务

#### 方式 A: Data Parallel (DP) — 推荐

适合 MoE 模型，将模型权重复制到多个 NPU，每个设备处理独立请求批次。

**节点 0（主节点）：**

```bash
nic_name="<网卡名>"
local_ip="<本机IP>"

export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name

vllm serve /path/to/model \
    --host 0.0.0.0 \
    --port 8004 \
    --data-parallel-size <总DP数> \
    --data-parallel-size-local <每节点DP数> \
    --data-parallel-address $local_ip \
    --data-parallel-rpc-port 13389 \
    --tensor-parallel-size <TP数> \
    --enable-expert-parallel \
    --max-model-len 8192 \
    --trust-remote-code \
    --gpu-memory-utilization 0.9
```

**节点 1（从节点）：**

```bash
nic_name="<网卡名>"
local_ip="<本机IP>"

export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name

vllm serve /path/to/model \
    --host 0.0.0.0 \
    --port 8004 \
    --headless \
    --data-parallel-size <总DP数> \
    --data-parallel-size-local <每节点DP数> \
    --data-parallel-start-rank <本节点起始rank> \
    --data-parallel-address <主节点IP> \
    --data-parallel-rpc-port 13389 \
    --tensor-parallel-size <TP数> \
    --enable-expert-parallel \
    --max-model-len 8192 \
    --trust-remote-code \
    --gpu-memory-utilization 0.9
```

#### 方式 B: Ray 集群 (TP 跨节点)

适合大模型的张量并行拆分。

**前置准备：**

1. 两台机器需导入相同镜像，模型放在相同路径（如 `/data/models/xxx`）
1. 配置 SSH 免密登录，方便远程操作

**Step 1: 各节点启动容器（daemon 模式常驻）**

```bash
bash run_container.sh --multi-node --daemon
```

**Step 2: 启动 Ray 集群**

使用 `ray_cluster.sh` 从本机一键管理（默认第一个 IP 为 head，其余为 worker）：

```bash
# 启动集群
bash ray_cluster.sh start

# 查看状态
bash ray_cluster.sh status

# 停止集群
bash ray_cluster.sh stop
```

也可手动指定节点：

```bash
bash ray_cluster.sh start --head 10.42.15.194 --workers 10.42.15.195 10.42.15.196
```

**Step 3: 主节点启动服务**

```bash
vllm serve /data/models/Qwen3-235B-A22B \
    --distributed-executor-backend ray \
    --tensor-parallel-size 16 \
    --enforce-eager \
    --trust-remote-code \
    --max-model-len 4096 \
    --port 8080
```

> **关键参数说明：**
> - `--distributed-executor-backend ray`：必须指定，否则 vLLM 默认用 multiproc executor（单机）
> - `--enforce-eager`：跨机 TP 时 ACL Graph 捕获会超出 NPU stream 资源上限，必须跳过
> - `--enable-expert-parallel`：MoE 模型（如 Qwen3-235B）建议开启专家并行

**实际部署示例（Qwen3-235B-A22B，2 节点 × 8 芯片 = 16 NPU）：**

| 节点 | IP | 网卡 | 角色 |
|------|-----|------|------|
| 本机 | 10.42.15.194 | enp66s0f0 | Head |
| 远程 | 10.42.15.195 | enp66s0f0 | Worker |

### 多机环境变量说明

| 变量 | 说明 |
|------|------|
| `HCCL_IF_IP` | 本机 IP，用于 HCCL 通信 |
| `GLOO_SOCKET_IFNAME` | Gloo 通信网卡名 |
| `TP_SOCKET_IFNAME` | Tensor Parallel 通信网卡名 |
| `HCCL_SOCKET_IFNAME` | HCCL Socket 通信网卡名 |
| `ASCEND_RT_VISIBLE_DEVICES` | 可见的 NPU 设备 (默认 0-7) |


## 网络配置
由于云脑3不支持直接联网，如果需要访问外部资源：

1. 请先建立 SSH 反向代理进行联网。
1. 必须配置 Docker 网关/代理设置，否则 Docker 容器内无法识别到宿主机的 SSH 代理。
1. 启动容器。
