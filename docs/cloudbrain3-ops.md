# Linux 常用运维命令速查

> 汇总 Linux 文件操作、远程传输、用户管理、代理配置等常用命令。

---

## 目录

- [1. 本地文件操作 (cp)](#1-本地文件操作-cp)
- [2. 远程文件传输 (scp)](#2-远程文件传输-scp)
- [3. 远程文件同步 (rsync)](#3-远程文件同步-rsync)
- [4. 用户与权限管理](#4-用户与权限管理)
- [5. 代理设置与取消](#5-代理设置与取消)

---

## 1. 本地文件操作 (cp)

### 常用参数

| 参数       | 含义                                                   |
| :--------- | :----------------------------------------------------- |
| `-r` / `-R` | 递归复制，用于复制目录及其所有内容。                   |
| `-a`       | 归档模式，保留权限、时间戳、符号链接等属性。           |
| `-f`       | 强制覆盖，不提示。                                     |
| `-i`       | 交互模式，覆盖前询问。                                 |
| `-v`       | 显示详细复制过程。                                     |

### 常见场景

```bash
# 复制单个文件
cp source_file target_file

# 复制整个文件夹
cp -r src_folder/ backup_folder/

# 备份配置文件（保留原有属性）
cp -a config.yaml config.yaml.bak

# 强制覆盖不提示
cp -rf new_version/ current_version/
```

---

## 2. 远程文件传输 (scp)

基于 SSH 协议的安全文件传输，适合临时传输少量文件。

### 常用参数

| 参数        | 含义                               |
| :---------- | :--------------------------------- |
| `-r`        | 递归复制整个目录。                 |
| `-P <端口>` | 指定远程主机 SSH 端口（大写 P）。  |
| `-C`        | 传输时压缩数据。                   |
| `-p`        | 保留原文件修改时间、权限（小写 p）。|

### 常见场景

```bash
# 上传文件到远程服务器
scp local_file.txt user@192.168.1.10:/home/user/

# 上传目录
scp -r local_dir/ user@192.168.1.10:/home/user/remote_dir/

# 从远程服务器下载文件
scp user@192.168.1.10:/remote/path/file.txt ./local_dir/

# 指定端口传输
scp -P 2222 file.txt user@host:/path/
```

> **注意**：`scp` 不支持断点续传，传输大文件建议使用 `rsync`。

---

## 3. 远程文件同步 (rsync)

功能强大的文件同步工具，支持增量备份和断点续传。

### 断点续传黄金组合

```bash
rsync -avzP --append-verify source_file destination
```

| 参数                | 含义                                               |
| :------------------ | :------------------------------------------------- |
| `-a` (archive)      | 归档模式，保留权限、时间戳、软链接等属性。         |
| `-v` (verbose)      | 详细输出。                                         |
| `-z` (compress)     | 传输时压缩数据，节省带宽。                         |
| `-P`                | 等同于 `--partial --progress`，保留中断的部分文件并显示进度。 |
| `--append-verify`   | 续传时从旧文件末尾添加并校验，确保数据完整。       |

### 常见场景

```bash
# 本地目录备份
rsync -av /home/user/data/ /mnt/backup/data/

# 远程同步（最常用）
rsync -avzP -e ssh ./local_folder/ root@192.168.1.100:/remote_folder/

# 跳过已存在文件
rsync -av --ignore-existing source_dir/ user@host:dest_dir/

# 镜像同步（目标与源完全一致，慎用）
rsync -av --delete /src/ /dest/

# 排除特定文件
rsync -av --exclude='node_modules' --exclude='.git' ./project/ ./backup/
```

> **注意斜杠**：`data/`（有斜杠）表示同步目录下的内容；`data`（无斜杠）表示把整个目录连同名字一起拷贝。

### 安全建议

执行 `--delete` 或处理重要数据前，先加 `-n` (`--dry-run`) 模拟运行：

```bash
rsync -av --delete --dry-run /src/ /dest/
```

### 常见问题排查

| 现象         | 原因及对策                                                                  |
| :----------- | :-------------------------------------------------------------------------- |
| **权限报错** | 目标目录无写入权限。尝试在目标路径前加 `sudo`。                             |
| **速度很慢** | 检查是否开启了 `-z` 压缩；小文件极多时 rsync 扫描时间会较长。               |
| **连接中断** | 直接重新运行上一条命令。配合 `-P` 参数，rsync 会自动跳过已完成的部分。      |

---

## 4. 用户与权限管理

### 创建用户

以创建用户 `jianzhnie` 为例：

```bash
sudo useradd -m -s /bin/bash jianzhnie
sudo passwd jianzhnie
```

可选：添加到管理组（CentOS/RHEL/Fedora 常用 `wheel`）：

```bash
sudo usermod -aG wheel jianzhnie
```

### 目录权限调整

```bash
# 递归修改目录所有者
sudo chown -R jianzhnie:jianzhnie /home/jianzhnie/llmtuner/hfhub/

# 递归修改目录权限
sudo chmod -R 755 /path/to/dir/
```

---

## 5. 代理设置与取消

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

- 编辑 `/etc/profile`，删除或注释掉 `export ...` 行
- 重新登录，或执行 `source /etc/profile`
