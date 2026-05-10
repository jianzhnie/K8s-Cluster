# CloudBrain3 运维速查

用于记录机柜节点登录、跳板访问、用户与权限、代理、路由等常用操作。

## 目录

- [CloudBrain3 运维速查](#cloudbrain3-运维速查)
  - [目录](#目录)
  - [目录权限调整](#目录权限调整)
  - [创建用户](#创建用户)
  - [代理设置与取消](#代理设置与取消)
    - [设置代理（全局生效：/etc/profile）](#设置代理全局生效etcprofile)
    - [取消代理](#取消代理)


## 目录权限调整

```bash
sudo chown -R jianzhnie:jianzhnie /home/jianzhnie/llmtuner/hfhub/
```

## 创建用户

以创建用户 `jianzhnie` 为例：

```bash
sudo useradd -m -s /bin/bash jianzhnie
sudo passwd jianzhnie
```

可选：添加到管理组（CentOS/RHEL/Fedora 常用 `wheel`）：

```bash
sudo usermod -aG wheel jianzhnie
```

## 代理设置与取消

### 设置代理（全局生效：/etc/profile）

编辑 `/etc/profile`，在末尾添加：

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export ftp_proxy=http://127.0.0.1:7897
export no_proxy="localhost,127.0.0.1,::1"
```

保存后执行：

```bash
source /etc/profile
```

### 取消代理

临时取消（仅当前终端会话生效）：

```bash
unset http_proxy
unset https_proxy
unset ftp_proxy
unset no_proxy
```

永久取消：

- 再次编辑 `/etc/profile`，删除或注释掉上面的 `export ...` 行
- 重新登录，或执行 `source /etc/profile` 使其生效
