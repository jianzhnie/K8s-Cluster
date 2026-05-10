# pengcheng-ailab 集群节点扩容

> 协同编辑表格：[《4500P计算节点带内管理IP》](https://www.yuque.com/g/elddriver/okti7b/xcq7y5gvv8dmtixm/collaborator/join?token=LzQTLeUIL1aCIkDb&source=doc_collaborator)。表格中标黄部分为已添加进入集群的节点，请在新节点添加后同步更新。

## 目录

- [节点预处理](#节点预处理)
  - [编写 Ansible 节点清单](#编写-ansible-节点清单)
  - [检查 Docker 状态并卸载](#检查-docker-状态并卸载)
  - [调整 /apps 目录挂载位置](#调整-apps-目录挂载位置)
  - [添加路由](#添加路由)
  - [创建必要目录](#创建必要目录)
- [Ansible 命令参数说明](#ansible-命令参数说明)
- [扩容节点](#扩容节点)
- [故障回退](#故障回退)
  - [清理节点](#清理节点)
  - [重新添加节点](#重新添加节点)

---

## 节点预处理

以下操作均在集群管理节点 `10.42.29.130` 上执行。

### 编写 Ansible 节点清单

在管理节点 `/etc/ansible` 目录下创建 hosts 文件，将需要扩容的节点 IP 写入：

```bash
cd /etc/ansible
vi hostsxxx
```

文件内容格式如下（节点账号密码配置参考同目录下 `hosts0206`）：

```ini
[01]               # 机框号，每个机框对应 16 个节点
ip1
ip2
...

[02]
ip1
ip2
...
```

### 检查 Docker 状态并卸载

预装的 Docker 中的 containerd 与集群所用的 containerd 冲突，需要先卸载 Docker。

**1) 检查 Docker 是否在运行，是否有容器正在运行：**

```bash
ansible -i hostsxxx all -m shell -a "docker ps"
```

**2) 若有容器在运行，先关停并删除：**

```bash
ansible -i hostsxxx all -m shell -a "docker ps -aq | xargs -r docker stop"
ansible -i hostsxxx all -m shell -a "docker ps -aq | xargs -r docker rm"
```

**3) 卸载 Docker：**

```bash
ansible -i hostsxxx all -m shell -a 'yum remove -y docker-ce docker-ce-cli containerd.io'
```

### 调整 /apps 目录挂载位置

节点根目录仅 400G，而 `/home` 目录有 6.6T，因此将 `/apps` 通过软链接指向 `/home/apps`：

```bash
ansible -i hostsxxx all -m shell -a "mkdir -p /home/apps"
ansible -i hostsxxx all -m shell -a "ln -s /home/apps /apps"
```

验证挂载是否成功：

```bash
ansible -i hostsxxx all -m shell -a "ls -l /apps"
# 预期输出：/apps -> /home/apps
```

### 添加路由

```bash
ansible -i hostsxxx all -m shell -a "ip rule add priority 5 to 172.25.0.0/14 lookup main"
```

### 创建必要目录

```bash
ansible -i hostsxxx all -m shell -a \
  "mkdir -p /var/log/mindx-dl/devicePlugin \
            /var/log/mindx-dl/noded \
            /var/log/mindx-dl/npu-exporter"
```

---

## Ansible 命令参数说明

| 参数 | 说明 |
|------|------|
| `-i` | 指定节点清单文件（hosts 文件） |
| `all` | 作用于清单中所有节点；也可指定分组名，如 `01` 仅作用于 `[01]` 分组 |
| `-m` | 指定模块：`shell`（执行命令）、`copy`（分发文件）、`script`（执行脚本）等 |
| `-a` | 传递给模块的参数 |

---

## 扩容节点

登录 kcs-estack 首页，进入「容器服务 - 管理控制台」，选择集群 `pengcheng-ailab`。

1. 左侧点击「节点管理」→「扩容」
2. 输入节点 IP（连续 IP 可用短横线，如 `10.42.10.1-10.42.10.19`）
3. 选择节点标签 `910C`，输入节点账号密码，点击确认

**监视扩容日志：**

```bash
# 登录管理节点 10.42.201.1
kubectl get po -n ecloud-eki              # 查看 eki 管理 pod 名称
kubectl logs -f -n ecloud-eki <pod-name>  # 查看实时日志
```

> 一个机框（16 节点）约 20 分钟添加完成，日志停止打印即表示完成。

也可通过节点数量确认：

```bash
kubectl get node -owide | grep '10.42.*' | wc -l
```

---

## 故障回退

若扩容过程中有节点添加失败，可清理后重新添加。

### 清理节点

回到集群 master1 节点（`10.42.29.130`）的 `/etc/ansible` 目录下操作。

**1) 编写待清理节点的清单文件：**

```bash
cd /etc/ansible
vi hostsxxx
```

```ini
[all]
ip1
ip2
# 节点账号密码配置参考 hosts0205 等文档
```

**2) 分发清理脚本至各节点：**

```bash
ansible -i hostsxxx all -m copy -a \
  "src=/etc/ansible/clean.sh dest=/root/ owner=root group=root mode=0644"
```

**3) 执行清理脚本：**

```bash
ansible -i hostsxxx all -m shell -a "bash /root/clean.sh"
```

**4) 清理 `/apps` 下残留目录：**

```bash
ansible -i hostsxxx all -m shell -a "rm -rf /apps/conf"
ansible -i hostsxxx all -m shell -a "rm -rf /apps/lib"
```

删除 `/apps/data` 前，需先取消相关挂载：

```bash
# 取消挂载
ansible -i hostsxxx all -m shell -a \
  "mount | grep '/apps/data/kubelet/pods' | awk '{print \$3}' | xargs -r umount"

# 再删除目录
ansible -i hostsxxx all -m shell -a "rm -rf /apps/data"
```

> **注意：** 直接删除 `/apps/data` 可能报错"目录正被挂载"，需先执行上述 umount 命令。

### 重新添加节点

按照[扩容节点](#扩容节点)流程，在页面上输入节点 IP、密码、标签，点击「添加」即可。观察日志确认是否添加成功。
