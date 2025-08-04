#!/bin/bash
set -eu

CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
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
    echo -e "$TIMESTAMP  \033[36mDEBUG\033[0m  $MSG"
    ;;
  info)
    echo -e "$TIMESTAMP  \033[32mINFO \033[0m  $MSG"
    ;;
  warn)
    echo -e "$TIMESTAMP  \033[33mWARN \033[0m  $MSG"
    ;;
  error)
    echo -e "$TIMESTAMP  \033[31mERROR\033[0m  $MSG"
    ;;
  *) ;;
  esac
}

get_os() {
  case "$(uname -s)" in
  Linux)   OS="linux" ;;
  Darwin)  OS="darwin" ;;
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

PLATFORM="$OS-$ARCH"
logger debug "platform: $PLATFORM"

DOWNLOAD_DIR="$CURRENT_DIR/$PLATFORM"
BACKUP_DIR="$CURRENT_DIR/backup"
TEMP_DIR="$CURRENT_DIR/temp"

download_with_urls() {
  pushd "$TEMP_DIR"
  [ "$#" -gt 0 ] || {
    logger warn "parameter is empty"
    return 1
  }

  for url in "$@"; do
    if [[ -e /usr/bin/wget ]]; then
      wget -c --no-check-certificate -T 10 -t 3 "$url" || {
        logger error "failed to wget download url, $url"
        return 1
      }
    else
      curl -L -k -O --connect-timeout 10 --max-time 60 --retry 3 "$url" || {
        logger error "failed to curl download url, $url"
        return 1
      }
    fi
  done
  popd
}

verify_sha256() {
  local file="$1"
  local hash_file="$2"

  actual_hash=$(sha256sum -b "$file" | awk '{print $1}')
  expected_hash=$(awk '{print $1}' "$hash_file")
  if [[ "$actual_hash" == "$expected_hash" ]]; then
    return 0
  else
    logger error "failed to verify the file: $file"
    logger warn "sha256 get : $actual_hash"
    logger warn "sha256 want: $expected_hash"
    return 1
  fi
}

# check_cmd_status "ls -l"
check_cmd_status() {
  logger debug "cmd: $1"
  local cmd="$1"
  local retries="${2:-30}" # 重试次数，默认为30次
  local interval="${3:-1}" # 间隔时间，默认为1秒

  for ((i = 1; i <= retries; i++)); do
    if bash -c "$cmd"; then
      logger debug "check cmd status is ready"
      return 0
    else
      logger warn "[$i] check cmd status is not ready, try again"
      sleep "$interval"
    fi
  done

  logger error "check cmd status is not ready in finally"
  return 1
}

download() {
  logger info "开始下载 docker 文件"

  if [[ ! -e "$DOWNLOAD_DIR" ]]; then
    mkdir -p "$DOWNLOAD_DIR"
  fi
  if [[ ! -e "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
  fi
  if [[ ! -e "$TEMP_DIR" ]]; then
    mkdir -p "$TEMP_DIR"
  fi

  backup_package="$BACKUP_DIR/$PLATFORM.tgz"
  if [[ -e "$backup_package" ]]; then
    logger info "发现并使用备份文件, $backup_package"
    tar -xzf "$backup_package" -C "$DOWNLOAD_DIR"
    logger info "下载 docker 文件成功, $DOWNLOAD_DIR"
    exit 0
  fi

  docker_temp_package="$TEMP_DIR/docker-$PLATFORM-$DOCKER_VERSION.tgz"
  if [[ -f "$docker_temp_package" ]]; then
    logger info "docker 文件已经存在，无需再次下载"
  else
    #  DOCKER_URL="https://download.docker.com/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    #  DOCKER_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    DOCKER_URL="https://mirrors.aliyun.com/docker-ce/${OS}/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    download_with_urls "$DOCKER_URL"
    mv "$TEMP_DIR/docker-$DOCKER_VERSION.tgz" "$docker_temp_package"
    logger info "下载 docker 完成, $docker_temp_package"
  fi

  tar -xzf "$docker_temp_package" --strip-components=1 -C "$DOWNLOAD_DIR"

  docker_compose_binary="docker-compose-${OS}-${ARCH}"
  docker_compose_backup_package="docker-compose-${OS}-${ARCH}-${DOCKER_COMPOSE_VERSION}.tgz"
  if [[ -f "$BACKUP_DIR/$docker_compose_backup_package" ]]; then
    logger info "使用备份的 docker-compose, $BACKUP_DIR/$docker_compose_backup_package"
    tar -xzf "$BACKUP_DIR/$docker_compose_backup_package" -C "$TEMP_DIR"
  else
   # https://github.com/docker/compose/releases/download/v2.37.2/docker-compose-linux-x86_64
    DOCKER_COMPOSE_URL="https://ghfast.top/https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}"
    logger info "下载 docker-compose, $DOCKER_COMPOSE_URL"

    if download_with_urls "$DOCKER_COMPOSE_URL" "$DOCKER_COMPOSE_URL.sha256" && verify_sha256 "$TEMP_DIR/$docker_compose_binary" "$TEMP_DIR/$docker_compose_binary.sha256"; then
      logger info "docker-compose 下载成功"
      tar -C "$TEMP_DIR" -czf "$BACKUP_DIR/$docker_compose_backup_package" "$docker_compose_binary" "$docker_compose_binary.sha256"
    else
      logger error "docker-compose 下载失败"
      exit 1
    fi
  fi

  cp -f "$TEMP_DIR/$docker_compose_binary" "$DOWNLOAD_DIR/docker-compose"
  chmod +x "$DOWNLOAD_DIR/docker-compose"

  logger info "所有 docker 文件下载完成, ls -lah $DOWNLOAD_DIR"
  ls -lah "$DOWNLOAD_DIR"

  logger info "备份 docker $PLATFORM 文件至 $BACKUP_DIR"
  pushd "$DOWNLOAD_DIR"
  tar -czf "$PLATFORM.tgz" ./*
  mv "$PLATFORM.tgz" "$BACKUP_DIR"
  popd

  logger info "docker $PLATFORM 备份成功"
}

install() {
  logger info "开始离线安装 docker"

  sudo systemctl is-active docker && {
    logger warn "docker 已经在运行中，安装终止"
    return 0
  }

  if [ -e "$BACKUP_DIR/$PLATFORM.tgz" ]; then
    logger info "docker 安装包已存在，使用该安装包, $BACKUP_DIR/$PLATFORM.tgz"
    tar -xzvf "$BACKUP_DIR/$PLATFORM.tgz" -C /usr/local/bin/

    sudo mkdir -pv /usr/local/lib/docker/cli-plugins
    sudo mv /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
  else
    logger error "docker 安装包不存在，请下进行下载，$BACKUP_DIR/$PLATFORM.tgz"
    return 1
  fi

  logger debug "生成 /etc/systemd/system/docker.service"
  cat >"/etc/systemd/system/docker.service" <<EOF
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
    mkdir -p "/etc/docker"
  fi

  DAEMON_FILE="/etc/docker/daemon.json"
  if [ -e "$DAEMON_FILE" ]; then
    DAEMON_FILE="/etc/docker/daemon.json.backup"
  fi

  cat >"$DAEMON_FILE" <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.nju.edu.cn/",
    "https://kuamavit.mirror.aliyuncs.com"
  ],
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2376"],
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

  logger debug "配置并启动 docker"
  sudo systemctl enable docker
  sudo systemctl daemon-reload && sudo systemctl restart docker

  if check_cmd_status "systemctl is-active docker"; then
    check_cmd_status "docker info" 30 3 && logger info "离线安装 docker 成功"
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
  read -t 30 -n1 -p "开始卸载 docker，是否确定? [Y/N]? " -r answer
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
  fi

  (
    set -x
    sudo systemctl disable docker
    sudo rm -rf /etc/systemd/system/docker.service
    sudo rm -rf /etc/docker/daemon.json
    sudo rm -rf /usr/local/bin/containerd /usr/local/bin/containerd-shim-runc-v2 /usr/local/bin/ctr /usr/local/bin/docker /usr/local/bin/docker-init /usr/local/bin/docker-proxy /usr/local/bin/dockerd /usr/local/bin/runc /usr/local/lib/docker/cli-plugins/docker-compose
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd
    sudo systemctl daemon-reload
  )

  # 清除 Bash 的可执行文件路径缓存
  hash -r

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
