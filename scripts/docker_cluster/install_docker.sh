#!/bin/bash

# Step1: 分发安装包
ansible -i hosts all -m copy -a "src=/root/containerd/docker.tar dest=/root/ owner=root group=root mode=0644"
#解压
ansible -i hosts all -m shell -a "tar xvf /root/docker.tar"
#执行脚本
ansible -i hosts all -m script -a "./docker-install.sh"


# Step2: 安装 Docker
cp /root/docker/docker /usr/local/bin/
cp /root/docker/dockerd /usr/local/bin/
cp /root/docker/docker-init /usr/local/bin/
cp /root/docker/docker-proxy /usr/local/bin/

mv /root/docker/docker.service /etc/systemd/system/
mv /root/docker/daemon.json /etc/docker/

systemctl daemon-reload && systemctl start docker
