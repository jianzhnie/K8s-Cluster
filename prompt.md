# 集群环境初始化

> 按顺序完成以下三步，将 14 台昇腾节点从裸机配置到容器就绪状态。

## 前置条件

| 项目 | 说明 |
|------|------|
| 节点列表 | `node_list2.txt`（14 台，10.1.1.x 网段） |
| 登录凭据 | 用户 `root`，密码 `iX5@vSogl9` |
| 本机依赖 | `sshpass`（免密配置和挂载阶段需要） |

---

## Step 1：配置免密登录

生成统一密钥对并分发到所有节点，实现任意两节点 SSH 互通。

```bash
bash tools/setup_ssh_nopass.sh \
  -f node_list1.txt \
  -u root \
  -p 'Huawei12#$'
```

完成后脚本会自动验证节点间互联。

---

## Step 2：批量挂载存储

将共享存储 `/llmtuner` 以 `dtfs` 方式挂载到所有节点的 `/home/jianzhnie/llmtuner`。

```bash
bash tools/batch_mount.sh \
  -f node_list1.txt \
  -u root \
  -p 'Huawei12#$'
```

默认参数：`-t dtfs -s /llmtuner -d /home/jianzhnie/llmtuner -n 8`（并行度 8）。
已挂载的节点会自动跳过。

---

## Step 3：部署 Docker 容器

加载镜像并在所有节点启动容器（镜像和启动脚本由 `scripts/docker/docker_env.sh` 配置）。

```bash
bash /home/jianzhnie/llmtuner/llm/ascend-llm-ops/scripts/docker/manage_docker_containers.sh start \
  -f /home/jianzhnie/llmtuner/llm/ascend-llm-ops/node_list1.txt \
  -j 16
```

支持的操作：`start`（默认）| `stop` | `restart`。
如需重试失败节点可加 `-r 3`，保留日志加 `--keep-logs`。

当前活跃镜像配置（`docker_env.sh`）：
- 镜像：`ascend910c-cann8.5.1-torch2.9.0-vllm0.18.0:latest`
- 容器名：`npuslim-env`
- 启动脚本：`start_container/run_npuslim_container.sh`

