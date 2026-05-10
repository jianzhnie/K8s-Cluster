# 常用开发命令速查指南

本文档汇总了 Linux 开发中常用的文件操作、远程传输及 Docker 容器管理命令。

## 一、本地文件操作 (cp)

`cp` (Copy) 命令用于复制文件或目录。

### 1. 基础用法
```bash
# 复制单个文件
cp source_file target_file

# 复制文件到指定目录 (保持文件名)
cp source_file target_directory/
```

### 2. 常用参数
*   **`-r` 或 `-R`**: 递归复制，用于复制目录及其所有内容。
*   **`-a`**: 归档模式，尽可能保留文件的权限、时间戳、符号链接等属性（等同于 `-dR --preserve=all`）。
*   **`-f`**: 强制复制，如果目标文件已存在则直接覆盖不提示。
*   **`-i`**: 交互模式，覆盖前会询问用户。
*   **`-v`**: 显示详细的复制过程。

### 3. 常见场景
```bash
# 复制整个文件夹
cp -r src_folder/ backup_folder/

# 备份配置文件（保留原有属性）
cp -a config.yaml config.yaml.bak

# 强制覆盖不提示
cp -rf new_version/ current_version/
```

---

## 二、远程文件传输 (scp)

`scp` (Secure Copy)安全复制, 基于 SSH 协议进行安全文件传输，语法简单，适合临时传输少量文件。

### 基础语法
```bash
scp [参数] 源路径 目标路径
```

### 常用参数
*   **`-r`**: 递归复制整个目录。
*   **`-P <端口>`**: 指定远程主机的 SSH 端口（注意是大写的 P）。
*   **`-C`**: 传输时压缩数据。
*   **`-p`**: 保留原文件的修改时间、访问时间和权限模式（小写 p）。

### 常见场景
```bash
# 上传文件到远程服务器
scp local_file.txt user@192.168.1.10:/home/user/

# 上传目录到远程服务器
scp -r local_dir/ user@192.168.1.10:/home/user/remote_dir/

# 从远程服务器下载文件
scp user@192.168.1.10:/remote/path/file.txt ./local_dir/

# 指定端口传输
scp -P 2222 file.txt user@host:/path/
```

> **注意**：`scp` 不支持断点续传，传输大文件建议使用 `rsync`。


## 三、远程文件传输 (rsync)

`rsync` 是一个功能强大的文件同步工具，支持增量备份和断点续传。

### 1. 核心语法
```bash
rsync [选项] 源路径 目标路径
```

### 2. 实现断点续传的“黄金组合”
如果你在传输大文件（如几个 GB 的镜像或数据库备份）时担心连接中断，请务必使用以下参数：

```bash
rsync -avzP --append-verify source_file destination
```

**参数详解：**
*   **`-a` (archive):** 归档模式，保留权限、时间戳、软链接等所有属性。
*   **`-v` (verbose):** 详细输出，让你看到传输进度。
*   **`-z` (compress):** 传输时压缩数据，节省带宽。
*   **`-e ssh`**: 指定使用 ssh 协议。
*   **`-P`**: 等同于 `--partial --progress`。
    *   `--partial`: 保留传输中断的部分文件。
    *   `--progress`: 显示实时传输速度和剩余时间。
*   **`--append-verify`**: 续传时从旧文件末尾开始添加并校验，确保数据完整。

---

### 3. 常见使用场景

#### A. 本地目录备份（最简单）

将 `data` 文件夹同步到备份盘：

```bash
rsync -av /home/user/data/ /mnt/backup/data/

```

> **注意斜杠：** `data/`（有斜杠）表示同步目录下的内容；`data`（无斜杠）表示把整个目录连同名字一起拷贝过去。

#### B. 远程同步（最常用）

通过 SSH 将本地文件推送到远程服务器：

```bash
rsync -avzP -e ssh ./local_folder/ root@192.168.1.100:/remote_folder/

```

#### C. 跳过已存在文件 

`scp` 默认会覆盖目标文件，不支持跳过。推荐使用 `rsync` 的 `--ignore-existing` 参数。

```bash
# -a: 归档模式 (保留权限、时间等)
# -v: 显示详细信息
# --ignore-existing: 跳过接收端已存在的文件 (不更新)
rsync -av --ignore-existing source_dir/ user@host:dest_dir/
```

#### D. “镜像”同步 (慎用)**

如果你希望目标目录和源目录**完全一致**（源目录删了什么，目标目录也跟着删），使用 `--delete`：

```bash
rsync -av --delete /src/ /dest/

```

---

### 4. 进阶技巧：排除特定文件

如果你不想同步 `node_modules` 或 `.git` 文件夹，可以使用 `--exclude`：

```bash
rsync -av --exclude='node_modules' --exclude='.git' ./project/ ./backup/

```

---

### 5. 常见问题排查

| 现象         | 原因及对策                                                                  |
| ------------ | --------------------------------------------------------------------------- |
| **权限报错** | 目标目录无写入权限。尝试在目标路径前加 `sudo`（远程需确保远程用户有权限）。 |
| **速度很慢** | 检查是否开启了 `-z` 压缩；如果是小文件极多，rsync 扫描时间会较长。          |
| **连接中断** | 直接重新运行上一条命令。配合 `-P` 参数，rsync 会自动跳过已完成的部分。      |

---

### 💡 一个贴心的小建议

在执行带有 `--delete` 或者处理重要数据时，建议先加上 `-n` 或 `--dry-run` 参数：

```bash
rsync -av --delete --dry-run /src/ /dest/
```

这会模拟运行一次，告诉你**“如果真动手，我会删哪些、传哪些”**，确认无误后再去掉 `-n` 正式执行。

