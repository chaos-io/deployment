# deployment

shell deployment script

## 使用

```bash
./docker.sh download ubuntu x86_64
```


## QA 

1. 如何非root用户无权限
```bash
# 如果没有就建立 docker 组
sudo groupadd docker
# 要将当前用户添加到 docker 组。
# -aG 选项的含义是“追加到组中”，这里的 -a 表示 append（追加），-G 表示 groups（组）。
sudo usermod -aG docker $USER
# 重新登录终端，或立即刷新权限
newgrp docker

# 如何依旧无权限，确认 Docker 套接字的权限是否允许 docker 组访问，正确如下
ls -l /var/run/docker.sock
srw-rw---- 1 root docker 0 6月 22 22:10 /var/run/docker.sock 
# 如何不是docker组，或权限不到，进行修正
sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock
```
