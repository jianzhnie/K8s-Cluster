# Docker 常用命令参考手册

> 按使用频率和深度组织，从最常用命令逐步深入

## 目录

- [快速上手](#快速上手)
- [一、基础概念](#一基础概念)
- [二、容器生命周期管理](#二容器生命周期管理)
- [三、容器交互与调试](#三容器交互与调试)
- [四、镜像管理](#四镜像管理)
- [五、Dockerfile 编写](#五dockerfile-编写)
- [六、数据管理](#六数据管理)
- [七、网络管理](#七网络管理)
- [八、Docker Compose](#八docker-compose)
- [九、系统运维与清理](#九系统运维与清理)
- [十、安全与扫描](#十安全与扫描)
- [十一、实用技巧](#十一实用技巧)
- [附录：命令速查表](#附录命令速查表)

---

## 快速上手

```bash
# 1. 拉取并运行你的第一个容器
docker run -d --name hello -p 8080:80 nginx
# 访问 http://localhost:8080 即可看到 Nginx 欢迎页

# 2. 查看运行状态
docker ps

# 3. 查看日志
docker logs hello

# 4. 进入容器
docker exec -it hello sh

# 5. 停止并清理
docker stop hello && docker rm hello
```

---

## 一、基础概念

| 概念 | 说明 |
|------|------|
| **镜像 (Image)** | 只读模板，包含创建容器所需的文件系统与依赖 |
| **容器 (Container)** | 镜像的运行实例，拥有独立的文件系统、网络和进程空间 |
| **仓库 (Registry)** | 存放和分发镜像的服务（如 Docker Hub、阿里云 ACR） |
| **Dockerfile** | 构建镜像的指令文件，每条指令对应一个镜像层 |
| **Volume** | 持久化数据的机制，数据独立于容器生命周期 |
| **Network** | 容器间通信的虚拟网络 |

Docker 核心工作流：

```
编写 Dockerfile → docker build 构建镜像 → docker run 启动容器 → docker push 推送分享
```

---

## 二、容器生命周期管理

### 2.1 `docker run` — 创建并启动容器

```bash
docker run [OPTIONS] IMAGE [COMMAND] [ARG...]
```

**常用参数一览：**

| 参数 | 说明 | 示例 |
|------|------|------|
| `-d` | 后台运行（分离模式） | `docker run -d nginx` |
| `--name` | 指定容器名 | `--name my-nginx` |
| `-p` | 端口映射 `主机:容器` | `-p 8080:80` |
| `-P` | 自动映射所有 `EXPOSE` 端口到主机随机端口 | `-P` |
| `-v` | 挂载数据卷或目录 | `-v /host/data:/data` |
| `--tmpfs` | 挂载内存文件系统 | `--tmpfs /tmp:rw,size=100m` |
| `-e` | 设置环境变量 | `-e MYSQL_ROOT_PASSWORD=123` |
| `--env-file` | 从文件读取环境变量 | `--env-file .env` |
| `-w` | 指定工作目录 | `-w /app` |
| `-u` | 指定用户 | `-u node` |
| `-it` | 交互式 + 分配终端 | `-it ubuntu bash` |
| `--rm` | 容器停止后自动删除 | `--rm` |
| `--restart` | 重启策略 | `--restart=always` |
| `--init` | 使用 tini 作为 PID 1，正确处理信号 | `--init` |
| `--memory` | 内存限制 | `--memory=512m` |
| `--cpus` | CPU 限制 | `--cpus=1.0` |
| `--platform` | 指定平台 | `--platform linux/arm64` |
| `--network` | 指定网络 | `--network mynet` |
| `--privileged` | 赋予全部权限（谨慎使用） | `--privileged` |
| `--read-only` | 文件系统只读 | `--read-only` |
| `--health-cmd` | 健康检查命令 | `--health-cmd "curl -f http://localhost/"` |

**常用示例：**

```bash
# 后台启动 Nginx，映射端口，挂载目录
docker run -d --name web -p 8080:80 -v ./html:/usr/share/nginx/html nginx

# 交互式进入 Ubuntu
docker run -it --rm ubuntu bash

# 带资源限制和自动重启
docker run -d --name app --restart=always --memory=512m --cpus=1.0 myapp

# 带 init 进程（正确处理僵尸进程和信号传递）
docker run -d --init --name app myapp

# 自动映射 EXPOSE 端口
docker run -d -P nginx
docker port <容器>   # 查看自动映射的端口
```

**重启策略：**

| 策略 | 说明 |
|------|------|
| `no` | 默认，不自动重启 |
| `on-failure[:max]` | 非正常退出时重启，可设次数上限 |
| `always` | 总是重启；即使手动 `docker stop`，daemon 重启后容器仍会启动 |
| `unless-stopped` | 类似 `always`，但手动 `docker stop` 后 daemon 重启不会启动容器 |

### 2.2 启停与删除

```bash
docker start   <容器>          # 启动已停止的容器
docker stop    <容器>          # 优雅停止（发 SIGTERM，10s 后 SIGKILL）
docker stop -t 30 <容器>       # 指定超时时间
docker restart <容器>          # 重启容器
docker kill    <容器>          # 立即杀死（SIGKILL）
docker rm      <容器>          # 删除已停止的容器
docker rm -f   <容器>          # 强制删除运行中的容器
docker container prune         # 删除所有已停止的容器
```

---

## 三、容器交互与调试

### 3.1 查看容器状态

```bash
docker ps                      # 查看运行中的容器
docker ps -a                   # 查看所有容器（含已停止）
docker ps -q                   # 只输出容器 ID
docker ps -l                   # 查看最近创建的容器
docker ps -s                   # 显示容器磁盘占用
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"  # 自定义格式
docker ps --filter "name=web"  # 按名称过滤
docker ps --filter "status=running"  # 按状态过滤
```

### 3.2 查看详情与日志

```bash
docker inspect <容器>          # 查看容器完整配置（JSON）
docker logs    <容器>          # 查看全部日志
docker logs -f <容器>          # 实时跟踪日志（类似 tail -f）
docker logs --tail 100 <容器>  # 最后 100 行
docker logs --since 2h <容器>  # 最近 2 小时的日志
docker logs -t <容器>          # 显示时间戳
docker top     <容器>          # 查看容器内进程
docker stats                   # 所有容器资源使用情况（实时刷新）
docker stats --no-stream <容器>  # 一次性输出资源使用
docker diff    <容器>          # 查看容器文件系统变更（A-添加 C-修改 D-删除）
docker port    <容器>          # 查看端口映射
```

### 3.3 进入容器与执行命令

```bash
docker exec -it <容器> bash          # 进入容器（推荐）
docker exec -it <容器> sh            # 进入容器（无 bash 时用 sh）
docker exec <容器> ls /app           # 在容器内执行单条命令
docker exec -w /app <容器> ls        # 指定工作目录执行命令
docker exec -u root <容器> bash      # 以 root 身份进入
docker attach <容器>                  # 附加到容器主进程
```

> **`exec` vs `attach`**：`exec` 开启新进程，退出不影响容器；`attach` 连接到主进程，`Ctrl+C` 会停止容器。大多数场景用 `exec`。
> 使用 `Ctrl+P, Ctrl+Q` 可以从 `attach` 中安全脱离而不停止容器。

### 3.4 文件拷贝

```bash
docker cp <容器>:/app/log.txt ./              # 容器 → 主机
docker cp ./config.yml <容器>:/app/config.yml  # 主机 → 容器
docker cp <容器>:/app/. ./backup/              # 拷贝整个目录
```

---

## 四、镜像管理

### 4.1 搜索与拉取

```bash
docker search nginx                  # 在 Docker Hub 搜索镜像
docker search --limit 5 nginx        # 只显示前 5 个结果
docker pull nginx                    # 拉取最新标签（latest）
docker pull nginx:1.25               # 拉取指定标签
docker pull nginx@sha256:abc123...   # 按摘要拉取（确保精确版本）
docker pull --platform linux/arm64 nginx  # 拉取指定平台
```

### 4.2 查看与删除

```bash
docker images                        # 列出本地镜像
docker images -a                     # 含中间层镜像
docker images --filter "dangling=true"  # 只显示悬空镜像（<none>）
docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}"  # 自定义格式
docker rmi nginx:1.25                # 删除指定镜像
docker rmi $(docker images -q)       # 删除所有镜像（谨慎）
docker image prune                   # 清理悬空镜像
docker image prune -a                # 清理所有未使用的镜像
```

### 4.3 构建镜像

```bash
docker build -t myapp:v1 .                   # 从 Dockerfile 构建
docker build -t myapp:v1 -f custom.Dockerfile .  # 指定 Dockerfile
docker build --no-cache -t myapp:v1 .        # 不使用缓存（全量重建）
docker build --build-arg VERSION=1.0 -t myapp .  # 传递构建参数
docker build --target builder -t myapp .     # 多阶段构建中指定阶段
docker build --progress=plain -t myapp .     # 显示完整构建输出（非简略）
```

### 4.4 镜像导入导出与推送

```bash
docker save -o myapp.tar myapp:v1             # 导出为 tar 文件
docker load -i myapp.tar                       # 从 tar 文件导入
docker tag myapp:v1 myrepo/myapp:v1            # 打标签
docker push myrepo/myapp:v1                    # 推送到仓库
```

### 4.5 查看镜像信息

```bash
docker history myapp:v1               # 查看镜像层历史（命令及大小）
docker inspect myapp:v1               # 查看镜像完整配置
```

---

## 五、Dockerfile 编写

### 5.1 常用指令

```dockerfile
FROM node:20-alpine            # 基础镜像（必须为第一条有效指令）
WORKDIR /app                   # 设置工作目录（不存在会自动创建）
COPY package*.json ./          # 拷贝文件（推荐，语义明确）
ADD src.tar.gz /app/           # 高级拷贝：支持远程 URL 和自动解压 tar
RUN npm ci --only=production   # 构建时执行命令（每条 RUN 产生一个新层）
ENV NODE_ENV=production        # 设置环境变量（运行时可用）
ARG VERSION=latest             # 构建参数（仅构建时可用，不保留在最终镜像）
EXPOSE 3000                    # 声明端口（配合 docker run -P 自动映射）
USER node                      # 切换运行用户（安全最佳实践）
ENTRYPOINT ["node"]            # 入口点（不可被 run 命令行覆盖）
CMD ["server.js"]              # 默认参数（可被 run 命令行覆盖）
VOLUME ["/data"]               # 声明匿名数据卷
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/ || exit 1  # 健康检查
```

**指令选择建议：**

| 场景 | 推荐 | 原因 |
|------|------|------|
| 拷贝本地文件 | `COPY` | 语义清晰，推荐优先使用 |
| 解压 tar 或远程 URL | `ADD` | `COPY` 不支持 |
| 构建时变量 | `ARG` | 不留痕到最终镜像 |
| 运行时变量 | `ENV` | 容器运行时可访问 |

### 5.2 ENTRYPOINT vs CMD

| 组合方式 | `docker run myapp` 执行 | `docker run myapp test` 执行 |
|---------|------------------------|----------------------------|
| `ENTRYPOINT ["node"]` + `CMD ["server.js"]` | `node server.js` | `node test` |
| 只有 `CMD ["node", "server.js"]` | `node server.js` | `test`（整体替换） |
| 只有 `ENTRYPOINT ["node"]` | `node` | `node test`（追加） |

> 如果需要 `docker run --entrypoint` 覆盖入口点，必须用 exec 格式 `["..."]`。

### 5.3 多阶段构建

多阶段构建可以有效减小最终镜像体积，只保留运行所需文件。

```dockerfile
# ---- 阶段1：构建 ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- 阶段2：运行 ----
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK CMD curl -f http://localhost/ || exit 1
```

### 5.4 `.dockerignore` 示例

`.dockerignore` 可以排除不需要的文件，加速构建并减小镜像体积。

```
# Git
.git
.gitignore

# 依赖（构建时重新安装）
node_modules

# 构建产物
dist
build

# IDE
.vscode
.idea

# 杂项
*.md
*.log
.env
.env.*
docker-compose*.yml
Dockerfile
.dockerignore
```

### 5.5 最佳实践

- 优先使用 `alpine` 等精简基础镜像，减小攻击面和体积
- 合并 `RUN` 指令减少层数：`RUN apt-get update && apt-get install -y ... && rm -rf /var/lib/apt/lists/*`
- 利用构建缓存：将变化少的指令放前面（如 `COPY package.json` → `RUN npm install` → `COPY . .`）
- 善用 `.dockerignore` 排除无关文件
- 使用 `USER` 指定非 root 用户运行应用
- 多阶段构建分离编译依赖和运行环境
- 使用 `COPY --chown=user:group file .` 一步完成拷贝和权限设置

---

## 六、数据管理

### 6.1 三种挂载方式

| 类型 | 命令格式 | 说明 |
|------|---------|------|
| **命名卷 (Volume)** | `-v mydata:/data` | Docker 管理，推荐用于持久化数据 |
| **绑定挂载 (Bind Mount)** | `-v /host/path:/data` | 挂载主机目录，推荐用于开发 |
| **内存文件系统 (tmpfs)** | `--tmpfs /tmp:rw,size=100m` | 内存存储，容器停止即消失 |

### 6.2 Volume 命令

```bash
docker volume create mydata                  # 创建数据卷
docker volume ls                             # 列出数据卷
docker volume inspect mydata                 # 查看详情（含宿主机路径）
docker volume rm mydata                      # 删除数据卷
docker volume prune                          # 清理未使用的数据卷
```

### 6.3 Volume vs 绑定挂载

| 特性 | Volume | 绑定挂载 |
|------|--------|---------|
| 存储位置 | Docker 管理 (`/var/lib/docker/volumes/`) | 主机任意路径 |
| 可移植性 | 好 | 差（依赖主机路径） |
| 性能 | 略低（macOS/Windows） | 略高 |
| 适用场景 | 生产环境、数据库持久化 | 开发环境、代码热更新 |

---

## 七、网络管理

### 7.1 网络类型

| 类型 | 说明 | 适用场景 |
|------|------|---------|
| `bridge` | 默认，容器间通过虚拟网桥通信 | 单机多容器通信 |
| `host` | 直接使用主机网络，无端口映射 | 高性能网络需求 |
| `none` | 无网络 | 安全隔离、离线计算 |
| `overlay` | 跨主机通信 | Docker Swarm 集群 |
| `macvlan` | 容器拥有独立 MAC 地址，直接接入物理网络 | 需要独立 IP 的场景 |

### 7.2 常用命令

```bash
docker network ls                                # 列出网络
docker network create mynet                      # 创建自定义桥接网络
docker network create --subnet=172.20.0.0/16 --gateway=172.20.0.1 mynet  # 指定子网
docker network create --driver bridge --internal mynet  # 内部网络（无外网）
docker network inspect mynet                     # 查看详情
docker network rm mynet                          # 删除网络
docker network prune                             # 清理未使用网络

# 使用自定义网络（容器间可用容器名互访，推荐）
docker run -d --name app --network mynet myapp
docker run -d --name db  --network mynet mysql
# app 容器内可以用 mysql -h db 连接数据库

# 动态连接/断开运行中容器的网络
docker network connect mynet <容器>      # 运行中容器加入网络
docker network disconnect mynet <容器>   # 运行中容器脱离网络
```

---

## 八、Docker Compose

### 8.1 常用命令

```bash
docker compose up -d              # 后台启动所有服务
docker compose up -d --build      # 启动前重新构建镜像
docker compose up -d --force-recreate  # 强制重建容器（即使配置未变）
docker compose down               # 停止并删除容器、网络
docker compose down -v            # 同时删除数据卷
docker compose down --rmi all     # 同时删除镜像
docker compose ps                 # 查看服务状态
docker compose logs -f <服务>     # 跟踪日志
docker compose logs --tail 50     # 最后 50 行
docker compose exec <服务> bash   # 进入容器
docker compose build              # 重新构建镜像
docker compose build --no-cache   # 无缓存构建
docker compose pull               # 拉取最新镜像
docker compose restart <服务>     # 重启服务
docker compose config             # 验证并查看合并后的配置（排错利器）
docker compose images             # 查看服务使用的镜像
docker compose top                # 查看服务内进程
```

### 8.2 docker-compose.yml 示例

```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner        # 指定多阶段构建的阶段
    ports:
      - "8080:3000"
    environment:
      - DB_HOST=db
      - DB_PASSWORD=${DB_PASSWORD}  # 从 .env 文件读取
    depends_on:
      db:
        condition: service_healthy  # 等待 db 健康检查通过
    volumes:
      - .:/app                      # 开发时挂载代码实现热更新
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    develop:
      watch:
        - action: rebuild
          path: .
          target: /app

  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: myapp
    volumes:
      - db_data:/var/lib/mysql
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  db_data:
```

### 8.3 Compose Watch（开发热重载）

Compose Watch 可以在文件变更时自动同步或重建，替代传统的 volume 挂载开发方式。

```yaml
services:
  web:
    build: .
    ports:
      - "3000:3000"
    develop:
      watch:
        # 代码变更 → 同步到容器（无需重建）
        - action: sync
          path: ./src
          target: /app/src
        # 依赖变更 → 重建镜像
        - action: rebuild
          path: ./package.json
        # 配置变更 → 重启容器
        - action: sync+restart
          path: ./config.yaml
          target: /app/config.yaml
```

```bash
docker compose watch   # 启动 watch 模式
```

---

## 九、系统运维与清理

### 9.1 系统信息

```bash
docker info                       # 查看 Docker 系统信息（存储驱动、运行时等）
docker version                    # 查看 Docker 版本（Client + Server）
docker system df                  # 查看 Docker 磁盘使用概览
docker system df -v               # 详细磁盘使用（按镜像/容器/卷分类）
docker system events              # 实时事件流
docker system events --since "2024-01-01" --until "1h"  # 时间范围过滤
```

### 9.2 清理命令

```bash
# 一键清理（推荐定期执行）
docker system prune               # 清理：停止的容器 + 悬空镜像 + 未用网络 + 构建缓存
docker system prune -a            # 同上 + 所有未使用的镜像
docker system prune --volumes     # 同上 + 未使用的数据卷

# 按类别单独清理
docker container prune            # 停止的容器
docker image prune -a             # 未使用的镜像
docker volume prune               # 未使用的数据卷
docker network prune              # 未使用的网络
docker builder prune              # 构建缓存
```

---

## 十、安全与扫描

### 10.1 镜像安全扫描

```bash
# Docker Scout（Docker Desktop 内置）
docker scout cves myapp:v1                 # 扫描镜像 CVE 漏洞
docker scout recommendations myapp:v1     # 获取修复建议
docker scout quickview myapp:v1           # 快速安全概览

# Docker Scout 比较
docker scout compare --to myapp:v1 myapp:v2  # 比较两个版本的安全差异
```

### 10.2 安全最佳实践

- 使用官方或可信的基础镜像，优先选择 `alpine`/`slim` 变体
- 不要在镜像中硬编码密码或密钥，使用 `ARG`/`ENV` + 运行时注入
- 以非 root 用户运行：`USER nobody` 或自定义用户
- 定期更新基础镜像并重新构建
- 使用 `docker scan` 或 `docker scout` 定期扫描漏洞
- 使用 `--read-only` 文件系统配合 `--tmpfs` 限制写入
- 避免使用 `--privileged`，按需使用 `--cap-add`

---

## 十一、实用技巧

### 11.1 批量操作

```bash
# 停止所有运行中的容器
docker stop $(docker ps -q)

# 删除所有容器
docker rm $(docker ps -aq)

# 删除所有镜像
docker rmi $(docker images -q)

# 按 名称/状态 过滤并操作
docker ps -a --filter "status=exited" -q | xargs docker rm
docker ps -a --filter "name=dev-" -q | xargs docker stop
```

### 11.2 排查与调试

```bash
# 查看容器退出码（常见的：0=正常退出, 137=OOM, 139=段错误）
docker inspect <容器> --format='{{.State.ExitCode}}'

# 查看容器 IP
docker inspect <容器> --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# 查看容器日志并搜索
docker logs <容器> 2>&1 | grep -i error

# 导出容器文件系统（排查用）
docker export <容器> | tar -tf - | head -20

# 查看镜像层详细信息
docker history --no-trunc myapp:v1

# 对比两个容器的配置差异
diff <(docker inspect container1) <(docker inspect container2)
```

### 11.3 开发加速

```bash
# 启用 BuildKit 加速构建（支持缓存导入导出、并行构建）
DOCKER_BUILDKIT=1 docker build -t myapp .

# 多平台构建（需启用 buildx）
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 -t myapp .

# 利用缓存加速 CI 构建
docker buildx build --cache-from type=registry,ref=myrepo/myapp:cache \
                    --cache-to type=registry,ref=myrepo/myapp:cache,mode=max \
                    -t myapp .

# 实时监控容器资源（按 CPU 排序）
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | sort -k2 -h
```

---

## 附录：命令速查表

| 类别 | 命令 | 说明 |
|------|------|------|
| **容器** | `docker run` | 创建并启动容器 |
| | `docker ps` | 查看容器列表 |
| | `docker exec` | 在运行中的容器执行命令 |
| | `docker logs` | 查看容器日志 |
| | `docker stop / start / restart` | 容器生命周期管理 |
| | `docker rm` | 删除容器 |
| | `docker cp` | 主机与容器间拷贝文件 |
| **镜像** | `docker pull / push` | 拉取 / 推送镜像 |
| | `docker build` | 构建镜像 |
| | `docker images` | 查看本地镜像 |
| | `docker rmi` | 删除镜像 |
| | `docker tag` | 为镜像打标签 |
| | `docker save / load` | 导出 / 导入 tar |
| **数据** | `docker volume create / ls / rm` | 管理数据卷 |
| **网络** | `docker network create / ls / rm` | 管理网络 |
| **编排** | `docker compose up / down` | 管理多容器应用 |
| | `docker compose watch` | 开发热重载 |
| **系统** | `docker system df` | 磁盘使用 |
| | `docker system prune` | 清理资源 |
| **安全** | `docker scout cves` | 镜像漏洞扫描 |
