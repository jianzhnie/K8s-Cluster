# pengcheng-ailab 集群节点扩容

邀请你共同编辑表格 [《4500P计算节点带内管理IP.20260207004444791》](https://www.yuque.com/g/elddriver/okti7b/xcq7y5gvv8dmtixm/collaborator/join?token=LzQTLeUIL1aCIkDb&source=doc_collaborator)。表格中标黄部分为已添加进入集群的节点，请在新节点添加后同步更新表格。

## 节点预处理

### 编写 Ansible 节点清单 hosts 文档

在集群管理节点 10.42.29.130 上编写 Ansible 节点清单 hosts 文档，把需要加进去的节点写进去。当前 hosts 文档统一放在该机器的 `/etc/ansible` 目录下。

```bash
cd /etc/ansible
vi hostsxxx

# 以下为 hostsxxx 文本内容示例
[01]               # 机框号，对应一框 16 个节点
ip1
ip2
...
[02]
ip1
ip2
```

节点账号密码配置可参考同目录下其他文档的写法复制，例如 `hosts0206` 文档。

### 检查节点 Docker 状态并卸载

预装的 Docker 中的 containerd 与集群所用的 containerd 冲突，需要先卸载 Docker。流程如下：

- 检查节点上 Docker 是否还在运行，是否有容器正在运行：

```bash
ansible -i hostsxxx all -m shell -a "docker ps "
```

- 如果有容器仍在运行，则先关停容器并删除：
```bash
ansible -i hostsxxx all -m shell -a "docker ps -aq | xargs -r docker stop"
ansible -i hostsxxx all -m shell -a "docker ps -aq | xargs -r docker rm"
```

- 没有容器在运行后，开始卸载 Docker：

```bash
ansible -i hostsxxx all -m shell -a 'yum remove -y docker-ce docker-ce-cli containerd.io'
```

### 调整 /apps 目录挂载位置

因为节点预留的根目录太小只有 400G，而 `/home` 目录留了 6.6T，所以将集群主要使用的目录 `/apps` 挂在 `/home` 下，通过软链接来指向。

```bash
ansible -i hostsxxx all -m shell -a "mkdir -p /home/apps"
ansible -i hostsxxx all -m shell -a "ln -s /home/apps /apps"
```

- 检查是否挂载成功：
```bash
ansible -i hostsxxx all -m shell -a "ls -l /apps"

# 结果应该是：/apps -> /home/apps
```

### 添加路由

```bash
ansible -i hostsxxx all -m shell -a " ip rule add priority 5 to 172.25.0.0/14 lookup main"
```

### 添加目录

```bash
ansible -i hostsxxx all -m shell -a "mkdir -p /var/log/mindx-dl/devicePlugin && mkdir -p /var/log/mindx-dl/noded && mkdir -p /var/log/mindx-dl/npu-exporter"
```

ansible 命令参数解释：

- `-i` 指定使用的节点清单，也就是 hosts 文件
- `all` 表示作用于清单中的所有节点；也可以只针对部分节点，例如要作用在上文中按机框号划分 `[01]` 分组的节点，此处用 `01` 代替 `all` 即可
- `-m` 指定 Ansible 操作的模块，常见的有上文的 `shell`（在命令行执行命令）、`copy`（分发文件）、`script`（执行本机脚本）等
- `-a` 将引号内的字符串作为参数传递给对应模块

## 扩容节点

登录 kcs-estack 首页，选择「容器服务 - 管理控制台」，选择集群：`pengcheng-ailab`。

- 左侧点击「节点管理」，在集群节点列表中点击「扩容」
- 输入要添加的节点 IP，如连续的且有多个，可以用短横线连接，例如：`10.42.10.1-10.42.10.19`
- 选择节点标签为 `910C`，输入节点账号密码，点击确认开始扩容
- 监视集群扩容日志：
  - 登录管理节点：`10.42.201.1`
  - 查看 eki 管理 pod 对应名称：`kubectl get po -n ecloud-eki`
  - 查看 pod 日志：`kubectl logs -f -n ecloud-eki <pod-name>`

一个框16个节点大约20分钟添加完，当日志不再打印的时候说明添加完成，也可通过新增节点数来判断：

```bash
kubectl get node -owide |grep '10.42.*' |wc -l

# 新增节点数（* 表示添加节点所在子网段，如 19、20 等）
```

### 故障回退

- 万一在节点扩容过程中，有节点添加失败的情况，可以通过以下方式先清理节点，再重新添加：
- 清理节点
  回到集群master1节点（10.42.29.130）上的/etc/ansible目录下：

```bash
cd /etc/ansible
ls -l
# 可以看到有一个 clean.sh 脚本，编辑节点清单 hostsxxx，把需要批量清理的节点加入

vi hostsxxx
# 以下为 hostsxxx 文本内容示例
[all]
ip1
ip2

# 节点账号密码部分参考其他文档如 hosts0205 下方的写法
```

将脚本分发至待清理节点上，此处直接放在root目录下：

- 在当前目录下执行脚本分发流程：

```bash
ansible -i hostsxxx all -m copy -a "src=/etc/ansible/clean.sh dest=/root/ owner=root group=root mode=0644"
```

- 然后执行脚本执行流程：

```bash
ansible -i hostsxxx all -m shell -a "bash /root/clean.sh"
```

- 清理 `/apps` 下部分目录：

```bash
ansible -i hostsxxx all -m shell -a "rm -rf /apps/conf"
ansible -i hostsxxx all -m shell -a "rm -rf /apps/lib"
ansible -i hostsxxx all -m shell -a "rm -rf /apps/data"
```

- 注意，在删除 `/apps/data` 目录的时候可能会报错该目录下部分目录正被挂载，可先执行下面命令批量取消挂载：

```bash
ansible -i hostsxxx all -m shell -a  "mount | grep '/apps/data/kubelet/pods' | awk '{print $3}' | xargs -r umount"
```

- 然后再执行一次删除 `/apps/data` 删除操作即可

### 节点重新添加

同前文扩容流程，直接在页面上输入节点 IP、密码、标签，点击「添加」即可，观察后续添加过程是否有报错。
