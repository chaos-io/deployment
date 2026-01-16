#!/bin/bash
set -eu

DOCKER_VERSION=27.5.1
DOCKER_COMPOSE_VERSION=v2.37.2

usage() {
  echo -e "\033[33mUsage:\033[0m $0 <command> <os> <arch>"
  cat <<EOF

commands:
    download                        download docker package
    install | install_online        install docker
    uninstall | uninstall_online    uninstall docker
os:
    linux | darwin | windows
arch:
    x86_64 | aarch64

Use "$0 help <command>" for more information about a given command.
EOF
}

logger() {
  TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
  CALLER_FILE=$(caller 0 | awk '{print $3}')
  CALLER_LINE=$(caller 0 | awk '{printf "%-5s", $1}')
  MSG="$CALLER_FILE:$CALLER_LINE    $2"

  case "$1" in
  debug)
    echo -e "\033[36mDEBUG\033[0m  $TIMESTAMP  $MSG"
    ;;
  info)
    echo -e "\033[32mINFO \033[0m  $TIMESTAMP  $MSG"
    ;;
  warn)
    echo -e "\033[33mWARN \033[0m  $TIMESTAMP  $MSG"
    ;;
  error)
    echo -e "\033[31mERROR\033[0m  $TIMESTAMP  $MSG"
    ;;
  *) ;;
  esac
}

get_os() {
  case "$(uname -s)" in
  Linux) OS="linux" ;;
  Darwin) OS="darwin" ;;
  CYGWIN* | MINGW* | MSYS*) OS="windows" ;;
  esac
  echo "$OS" | tr '[:upper:]' '[:lower:]'
}

case "${2:-}" in
linux | darwin | windows) OS="$2" ;;
"") OS=$(get_os) ;;
*) logger error "illegal option: $1" && usage >&2 && return 1 ;;
esac
[ -z "$OS" ] && logger error "illegal os" && (usage >&2 && exit 2)

case "${3:-}" in
x86_64 | aarch64) ARCH="$3" ;;
"") ARCH=$(uname -m) ;;
*) logger error "illegal option: $1" && usage >&2 && return 1 ;;
esac
[ -z "$ARCH" ] && logger error "illegal arch" && (usage >&2 && exit 2)

download_url() {
  [ "$#" -gt 0 ] || {
    logger warn "url is empty"
    return 1
  }

  url=$1
  name=$2

  command -v wget >/dev/null 2>&1 && {
    wget -c --no-check-certificate -T 10 -t 3 \
      ${name:+-O "$name"} "$url"
  } || {
    curl -L -k --connect-timeout 10 --max-time 60 --retry 3 \
      ${name:+-o "$name"} "$url"
  } || {
    logger error "failed to download url, $url"
    return 1
  }
}

verify_sha256() {
  local file="$1"
  local hash_file="$2"
  # 参数与文件校验
  [[ -f "$file" ]] || {
    logger error "file not found: $file"
    return 2
  }

  [[ -f "$hash_file" ]] || {
    logger error "hash file not found: $hash_file"
    return 2
  }

  local actual_hash
  local expected_hash
  local hasher

  # 选择可用的 SHA-256 工具
  if command -v sha256sum >/dev/null 2>&1; then
    hasher=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hasher=(shasum -a 256)
  else
    logger error "no SHA-256 tool available"
    return 2
  fi

  # 计算实际 hash
  actual_hash="$("${hasher[@]}" "$file" | awk '{print $1}') | tr '[:upper:]' '[:lower:]'"
  expected_hash="$(awk '{print $1}' "$hash_file") | tr '[:upper:]' '[:lower:]'"

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    return 0
  fi

  logger error "SHA-256 verification failed"
  logger warn "file          : $file"
  logger warn "actual hash   : $actual_hash"
  logger warn "expected hash : $expected_hash"
  return 1
}

# check_cmd_status "ls -l"
check_cmd_status() {
  local cmd="$1"
  local retries="${2:-10}" # 重试次数，如果$2为空，则使用默认值10
  local interval="${3:-6}" # 间隔时间

  logger debug "cmd: $cmd"

  for ((i = 1; i <= retries; i++)); do
    if bash -c -- "$cmd"; then # 加上 -- 可以防止 $cmd 被当成 bash 参数
      logger debug "$cmd is ready"
      return 0
    fi
    logger warn "[$i/$retries] cmd is not ready, retrying..."
    sleep "$interval"
  done

  logger error "cmd is still not ready after $retries retries"
  return 1
}

# 脚本常量
PLATFORM="$OS-$ARCH"
WORKING_DIR=$(cd "$(dirname "$0")" && pwd)
logger debug "platform:$PLATFORM", "working dir:$WORKING_DIR"
PLATFORM_DIR="$WORKING_DIR/$PLATFORM"
BACKUP_DIR="$WORKING_DIR/backup"
TEMP_DIR="$WORKING_DIR/temp"
# DOCKER_URL="https://download.docker.com/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
# DOCKER_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
DOCKER_URL="https://mirrors.aliyun.com/docker-ce/${OS}/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
DOCKER_GPG_URL="https://download.docker.com/linux/debian/gpg"
# https://github.com/docker/compose/releases/download/v2.37.2/docker-compose-linux-x86_64
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}"
DOCKER="docker-$PLATFORM-$DOCKER_VERSION.tgz"
DOCKER_COMPOSE="docker-compose-${OS}-${ARCH}"

download() {
  logger info "开始下载 docker 文件"

  if [[ -e "$PLATFORM_DIR" ]]; then
    rm -rf "$PLATFORM_DIR"
  fi
  if [[ -e "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
  mkdir -p "$TEMP_DIR"
  if [[ ! -e "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
  fi

  pushd "$TEMP_DIR"

  logger info "docker 二进制下载"
  if [[ -f "$BACKUP_DIR/$DOCKER" ]]; then
    logger info "docker 文件已经存在，无需再次下载"
    cp "$BACKUP_DIR/$DOCKER" "."
  else

    download_url "$DOCKER_URL" "$DOCKER"
    logger info "下载 docker 完成, $DOCKER"
    cp "$DOCKER" "$BACKUP_DIR/$DOCKER"
  fi

  logger info "配置docker gpg"
  download_url "$DOCKER_GPG_URL" docker.asc

  logger info "docker-compose 二进制下载"
  if [[ -f "$BACKUP_DIR/$DOCKER_COMPOSE" ]]; then
    logger info "使用备份的 docker-compose"
    cp "$BACKUP_DIR/$DOCKER_COMPOSE" "$DOCKER_COMPOSE"
  else
    if [[ ! -e "$DOCKER_COMPOSE" ]]; then
      download_url "$DOCKER_COMPOSE_URL" "$DOCKER_COMPOSE"
    fi
    logger info "下载 docker-compose 完成"
    cp "$DOCKER_COMPOSE" "$BACKUP_DIR/$DOCKER_COMPOSE"
  fi

  if [[ ! -e "$DOCKER_COMPOSE.sha256" ]]; then
    download_url "$DOCKER_COMPOSE_URL.sha256" "$DOCKER_COMPOSE.sha256"
  fi

  if verify_sha256 "$DOCKER_COMPOSE" "$DOCKER_COMPOSE.sha256"; then
    logger info "验证 docker-compose 成功"
  else
    logger error "验证 docker-compose 失败"
    exit 1
  fi

  popd

  mv -f "$TEMP_DIR" "$PLATFORM_DIR"
  logger info "所有 docker 文件下载完成, ls -lh $PLATFORM_DIR"
  ls -lh "$PLATFORM_DIR"
}

install() {
  logger info "开始离线安装 docker"

  sudo systemctl is-active docker && {
    logger warn "docker 已经在运行中，安装终止"
    return 0
  }

  if [[ ! -e "$PLATFORM" ]]; then
    logger warn "docker 安装包不存在，进行下载"
    download
  fi

  pushd "$PLATFORM"
  logger info "开始安装 docker"
  sudo tar -xzvf "$DOCKER" --strip-components=1 -C /usr/local/bin/

  logger debug "添加 docker 官方 GPG key"
  sudo mkdir -p /etc/apt/keyrings
  sudo chmod 0755 /etc/apt/keyrings
  # sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo cp "docker.asc" /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  logger debug "添加 docker apt 源"
  sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo mkdir -pv /usr/local/lib/docker/cli-plugins
  sudo cp "$DOCKER_COMPOSE" /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

  popd

  logger debug "生成 /etc/systemd/system/docker.service"
  sudo tee /etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io
[Service]
Environment="PATH=/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin"
ExecStart=/usr/local/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF

  logger debug "生成 /etc/docker/daemon.json"
  if [[ ! -e "/etc/docker" ]]; then
    sudo mkdir -p "/etc/docker"
  fi

  now=$(date "+%Y-%m-%d-%H-%M-%S")
  DAEMON_FILE="/etc/docker/daemon.json"
  if [ -e "$DAEMON_FILE" ]; then
    DAEMON_FILE="/etc/docker/daemon.json-$now"
  fi

  sudo tee "$DAEMON_FILE" <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.nju.edu.cn/",
    "https://kuamavit.mirror.aliyuncs.com"
  ],
  "hosts": ["unix:///var/run/docker.sock"],
  "max-concurrent-downloads": 10,
  "log-driver": "json-file",
  "log-level": "warn",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
    },
  "data-root": "/var/lib/docker"
}
EOF

  logger debug "添加 proxy.conf"
  PROXY_DIR="/etc/systemd/system/docker.service.d"
  PROXY_FILE="$PROXY_DIR/proxy.conf"
  if [[ ! -e "$PROXY_DIR" ]]; then
    sudo mkdir -p "$PROXY_DIR"
  fi
  if [[ -e "$PROXY_FILE" ]]; then
    PROXY_FILE="$PROXY_DIR/proxy.conf-$now"
  fi

  sudo tee "$PROXY_FILE" <<EOF
#[Service]
#Environment="HTTP_PROXY=http://127.0.0.1:7890/"
#Environment="HTTPS_PROXY=http://127.0.0.1:7890/"
#Environment="NO_PROXY=localhost,127.0.0.1"
EOF

  logger debug "配置并启动 docker"
  sudo systemctl enable docker
  sudo systemctl daemon-reload && sudo systemctl restart docker

  if check_cmd_status "systemctl is-active docker"; then
    check_cmd_status "docker images" 10 6 && logger info "离线安装 docker 成功"
  else
    logger error "docker 没有启动成功，请手动检查状态"
  fi
}

install_online() {
  logger info "进行官方线上安装 docker"
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 containerd runc; do sudo apt-get remove $pkg; done
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh --dry-run
  sh get-docker.sh --version $DOCKER_VERSION --mirror Aliyun
  logger info "docker 线上安装成功"
}

read_uninstall_answer() {
  read -t 30 -n1 -p "开始卸载 docker，是否确定? [y/n]? " -r answer
  case $answer in
  Y | y)
    echo
    logger info "begin to uninstall"
    return 0
    ;;
  N | n)
    echo
    logger info "uninstall was aborted"
    return 1
    ;;
  esac

  logger info "uninstall timeout"
  return 1
}

uninstall_online() {
  logger info "进行官方线上卸载 docker"
  read_uninstall_answer || exit 1
  sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  sudo rm -rf /var/lib/docker
  sudo rm -rf /var/lib/containerd
  logger info "Uninstallation complete."
}

uninstall() {
  logger info "进行线下卸载 docker"
  read_uninstall_answer || exit 1

  if [[ "$(sudo systemctl is-active docker)" == active ]]; then
    logger info "停止正在运行的 docker"
    sudo systemctl stop docker
    sleep 2
  fi

  (
    now=$(date "+%Y-%m-%d-%H-%M-%S")
    set -x
    sudo systemctl disable docker
    sudo rm -rf /etc/systemd/system/docker.service
    sudo mv /etc/docker/daemon.json /etc/docker/daemon.json-"$now"
    sudo rm -rf /usr/local/bin/containerd /usr/local/bin/containerd-shim-runc-v2 /usr/local/bin/ctr /usr/local/bin/docker /usr/local/bin/docker-init /usr/local/bin/docker-proxy /usr/local/bin/dockerd /usr/local/bin/runc /usr/local/lib/docker/cli-plugins/docker-compose
    sudo mv /etc/systemd/system/docker.service.d/proxy.conf /etc/systemd/system/docker.service.d/proxy.conf-"$now"
    hash -r # 清除 Bash 的可执行文件路径缓存
    sudo systemctl daemon-reload
  )

  logger info "docker 卸载完成"
}

main() {
  [ "$#" -gt 0 ] || (usage >&2 && exit 2)

  case "$1" in
  download)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    download
    ;;
  install)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    install
    ;;
  uninstall)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    uninstall
    ;;
  install_online)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    install_online
    ;;
  uninstall_online)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    uninstall_online
    ;;
  *)
    logger error "illegal first parameter"
    usage && exit 0
    ;;
  esac
}

main "$@"
