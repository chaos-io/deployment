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
    ubuntu | centos | debian
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

# linux standard Base
get_distribution() {
  lsb_dist=""
  if [ -r /etc/os-release ]; then
    lsb_dist="$(. /etc/os-release && echo "$ID")"
  fi
  echo "$lsb_dist" | tr '[:upper:]' '[:lower:]'
}

case "${2:-}" in
ubuntu | centos | debian) LSB="$1" ;;
"") LSB=$(get_distribution) ;;
*) logger error "illegal option: $1" && usage >&2 && return 1 ;;
esac
[ -z "$LSB" ] && logger error "illegal os" && (usage >&2 && exit 2)

case "${3:-}" in
x86_64 | aarch64) ARCH="$1" ;;
"") ARCH=$(uname -m) ;;
*) logger error "illegal option: $1" && usage >&2 && return 1 ;;
esac
[ -z "$ARCH" ] && logger error "illegal arch" && (usage >&2 && exit 2)

PLATFORM="$LSB-$ARCH"
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
      curl -k -C- -O --connect-timeout 10 --max-time 60 --retry 3 "$url" || {
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

  if [[ "$(sha256sum -b "$file")" == "$(cat "$hash_file")" ]]; then
    return 0
  else
    logger error "failed to verify the file: $file"
    logger warn "sha256 get : $(sha256sum -b "$file")"
    logger warn "sha256 want: $(cat "$hash_file")"
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
  logger info "download docker"

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
    tar -xzvf "$backup_package" -C "$DOWNLOAD_DIR"
    exit 0
  fi

  docker_package="$TEMP_DIR/docker-$DOCKER_VERSION.tgz"
  if [[ -f "$docker_package" ]]; then
    logger warn "docker package already existed"
  else
    #  DOCKER_URL="https://download.docker.com/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    #  DOCKER_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    DOCKER_URL="https://mirrors.aliyun.com/docker-ce/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    download_with_urls "$DOCKER_URL"
    logger info "downloading docker binaries, $DOCKER_URL"
  fi

  tar -xzvf "$docker_package" --strip-components=1 -C "$DOWNLOAD_DIR"

  # https://github.com/docker/compose/releases/download/v2.37.2/docker-compose-linux-x86_64
  DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${ARCH}"
  DOCKER_COMPOSE_SHA256_URL="$DOCKER_COMPOSE_URL.sha256"

  docker_compose_package="$TEMP_DIR/docker-compose-linux-${ARCH}"
  docker_compose_backup_package="$BACKUP_DIR/docker-compose-linux-${ARCH}-${DOCKER_COMPOSE_VERSION}.tgz"
  if [[ -f "$docker_compose_backup_package" ]]; then
    logger info "use backup docker-compose, $docker_compose_backup_package"
    tar -xzvf "$docker_compose_backup_package" -C "$TEMP_DIR"
  else
    logger info "downloading docker-compose, $DOCKER_COMPOSE_URL"
    docker_compose_package_sha256="$TEMP_DIR/docker-compose-linux-${ARCH}.sha256"

    if download_with_urls "$DOCKER_COMPOSE_URL" "$DOCKER_COMPOSE_SHA256_URL" && verify_sha256 "$docker_compose_package" "$docker_compose_package_sha256"; then
      logger info "docker-compose download successfully"
      tar -czvf "docker-compose-linux-${ARCH}-${DOCKER_COMPOSE_VERSION}.tgz" "docker-compose-linux-${ARCH}" "docker-compose-linux-${ARCH}.sha256" -C "$TEMP_DIR"
      mv "$TEMP_DIR/docker-compose-linux-${ARCH}-${DOCKER_COMPOSE_VERSION}.tgz" "$BACKUP_DIR"
    else
      logger error "failed to download docker compose"
      exit 1
    fi
  fi

  cp -f "$docker_compose_package" "$DOWNLOAD_DIR/docker-compose"
  # rm "$docker_compose_package_sha256"
  chmod +x "$DOWNLOAD_DIR/docker-compose"

  logger info "docker all download successfully, ls -lah $DOWNLOAD_DIR"
  ls -lah "$DOWNLOAD_DIR"

  logger info "backup the $PLATFORM package"
  pushd "$DOWNLOAD_DIR"
  tar -czvf "$PLATFORM.tgz" ./*
  mv "$PLATFORM.tgz" "$BACKUP_DIR"
  popd

  logger info "docker backup successfully"
}

install() {
  logger info "Start the offline installation."

  systemctl is-system-running docker && {
    logger warn "docker is already running, the installation was aborted"
    return 0
  }

  logger info "docker was not running"
  if [ -e "$BACKUP_DIR/$PLATFORM.tgz" ]; then
    logger info "docker package was already existed"
    tar -xzvf "$BACKUP_DIR/$PLATFORM.tgz" -C /usr/local/bin/
  else
    logger info "docker package not exit, please download first"
    return 1
  fi

  logger debug "generate /etc/systemd/system/docker.service"
  cat >"/etc/systemd/system/docker.service" <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io
[Service]
Environment="PATH=/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin"
ExecStart=/usr/bin/dockerd
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

  logger debug "generate /etc/docker/daemon.json"
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

  logger debug "enable and start docker"
  systemctl enable docker
  systemctl daemon-reload && systemctl restart docker

  if check_cmd_status "systemctl is-system-running docker"; then
    check_cmd_status "docker info" 60 3 && logger info "install docker offline successfully"
  else
    logger error "docker not running, please check it manually"
  fi
}

install_online() {
  logger info "Start the official online installation."
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 containerd runc; do sudo apt-get remove $pkg; done
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh --dry-run
  sh get-docker.sh --version $DOCKER_VERSION --mirror Aliyun
  logger info "Installation complete."
}

read_uninstall_answer() {
  read -t 30 -n1 -p "Will be uninstall, are you sure? [Y/N]? " -r answer
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
  logger info "Start the official online uninstallation."
  read_uninstall_answer || exit 1
  sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  sudo rm -rf /var/lib/docker
  sudo rm -rf /var/lib/containerd
  logger info "Uninstallation complete."
}

uninstall() {
  logger info "Start the uninstallation."
  read_uninstall_answer || exit 1

  if [[ "$(systemctl is-system-running docker)" == active ]]; then
    logger info "docker is running, try to stop it"
    systemctl stop docker
  fi

  (
    set -x
    systemctl disable docker
    sudo rm -rf /etc/systemd/system/docker.service
    sudo rm -rf /etc/docker/daemon.json
    sudo rm -rf /usr/local/bin/containerd /usr/local/bin/containerd-shim-runc-v2 /usr/local/bin/ctr /usr/local/bin/docker /usr/local/bin/docker-compose /usr/local/bin/docker-init /usr/local/bin/docker-proxy /usr/local/bin/dockerd /usr/local/bin/runc
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd
    systemctl daemon-reload
  )

  logger info "Uninstallation complete."
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
