# deployment

ansible playbook

## 使用

1. 安装ansible
```bash
ansible all -m ping
```

2. 配置远程系统，并确保本机器的public SSH key必须在这些系统的authorized_keys中
```bash
cat > /etc/ansible/hosts << "EOF"
192.168.31.170
192.168.31.171
192.168.31.172
EOF
```
3. 执行命令

```bash
ansible-playbook docker.yml
```

## QA 
