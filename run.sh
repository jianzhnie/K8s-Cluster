## 挂载 dtfs 文件系统

## 挂载 dtfs 文件系统
mount -t dtfs  /llm_workspace_1P  /llm_workspace_1P

## 卸载 dtfs 文件系统
umount /llm_workspace_1P


## 挂载 dtfs 文件系统
mount -t dtfs /xufan_400T /mnt/xufan_400T

## 卸载 dtfs 文件系统
umount /mnt/xufan_400T

# 文件上传

## 同步本地文件到服务器
rsync -avz K8s-Cluster  root@10.42.29.130:/llm_workspace_1P/robin/
rsync -avz Kimi2-PCL  root@10.42.29.130:/llm_workspace_1P/robin/

# 从服务器下载文件
rsync -avz root@10.42.29.130:/llm_workspace_1P/robin/K8s-Cluster/scripts/pcl_scripts scripts/

## 在服务器上文件同步
# 上传 kimi 脚本
rsync -avz K8s-Cluster/scripts/kimi2 MindSpeed-LLM/examples/mcore/

# 上传 pcl 脚本
rsync -avz K8s-Cluster/scripts/pcl_scripts  MindSpeed-LLM/

# 上传 k8s 脚本
rsync -avz K8s-Cluster/k8scluster/*.sh  MindSpeed-LLM/scripts/

## K8S 节点标签
kubectl label nodes $(seq -f "bms%04g" 1 448) room=201 --overwrite
kubectl label nodes $(seq -f "bms%04g" 0997 1920) room=202 --overwrite
kubectl label nodes $(seq -f "bms%04g" 1889 1920) room=202 --overwrite


## 进入容器
docker exec -it mindspeed-llm-env /bin/bash

# 查找空闲节点
comm -23 \
  <(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers | sort -u) \
  <(kubectl get pod -A -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
    | awk '$1 ~ /^fdd-kimi2-1t-no-recompute-768-nodes/ {print $2}' \
    | sort -u) > /llm_workspace_1P/robin/K8s-Cluster/free_nodes.txt


# 检查空闲节点是否存在模型目录
MAX_PARALLEL=100 bash check_dir.sh \
  /llm_workspace_1P/robin/K8s-Cluster/free_nodes.txt \
  /llm_workspace_1P/robin/hfhub \
  exist_nodes.txt \
  missing_nodes.txt

# 挂载缺失节点的模型目录
PARALLEL=128 RETRIES=1 SSH_MUX=1 bash /llm_workspace_1P/robin/K8s-Cluster/scripts/mount_dpc.sh \
  /llm_workspace_1P/robin/K8s-Cluster/missing_nodes.txt

# 查找NPU 空闲节点
bash /llm_workspace_1P/robin/K8s-Cluster/scripts/find_null_node.sh \
  /llm_workspace_1P/robin/K8s-Cluster/exist_nodes.txt
