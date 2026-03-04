## 文件上传


## 同步本地文件到服务器

```sh
rsync -avz K8s-Cluster  root@10.42.29.130:/mnt/9w1N7vBPmO3wMAYjqZL/robin/
```

## 在服务器上文件同步

```sh
# 上传 kimi 脚本
scp -r K8s-Cluster/scripts/kimi2 MindSpeed-LLM/examples/mcore/

# 上传 k8s 脚本
scp -r K8s-Cluster/k8scluster/*.sh  MindSpeed-LLM/scripts/
```


## K8S 节点标签
kubectl label nodes $(seq -f "bms%04g" 1 448) room=201 --overwrite
kubectl label nodes $(seq -f "bms%04g" 0997 1920) room=202 --overwrite
kubectl label nodes $(seq -f "bms%04g" 1889 1920) room=202 --overwrite


## 进入容器
docker exec -it mindspeed-llm-env /bin/bash