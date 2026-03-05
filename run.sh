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
rsync -avzP Qwen3.tar root@10.42.29.130:/llm_workspace_1P/robin/hfhub/models/Qwen 

rsync -avz K8s-Cluster  root@10.42.29.130:/llm_workspace_1P/robin/


# 从服务器下载文件
rsync -avz root@10.42.29.130:/llm_workspace_1P/robin/MindSpeed-LLM/pcl_scripts scripts/


## 在服务器上文件同步
# 上传 kimi 脚本
scp -r K8s-Cluster/scripts/kimi2 MindSpeed-LLM/examples/mcore/

# 上传 k8s 脚本
scp -r K8s-Cluster/k8scluster/*.sh  MindSpeed-LLM/scripts/

## K8S 节点标签
kubectl label nodes $(seq -f "bms%04g" 1 448) room=201 --overwrite
kubectl label nodes $(seq -f "bms%04g" 0997 1920) room=202 --overwrite
kubectl label nodes $(seq -f "bms%04g" 1889 1920) room=202 --overwrite


## 进入容器
docker exec -it mindspeed-llm-env /bin/bash