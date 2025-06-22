#!/bin/bash

set -eu

CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
TERRAFORM_VERSION=1.9.8

ARCH=$(uname -m)
#ARCH=aarch64
BACKUP_DIR="$CURRENT_DIR/backup"
BACKUP_PACKAGE="$BACKUP_DIR/terraform-$TERRAFORM_VERSION-linux-$ARCH.tgz"

usage() {
  echo -e "\033[33mUsage:\033[0m $0 <command>"
  cat <<EOF

commands:
    install            install online
    download           download package
    install_offline    install online by backup package
    uninstall          uninstall
    uninstall_offline  uninstall that install_offline

Use "$0 help <command>" for more information about a given command.
EOF
}

# eg: logger warn "logs warn"
logger() {
  TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
  CALLER_LINE=$(caller 0 | awk '{print $1}')
  CALLER_FILE=$(caller 0 | awk '{print $3}')
  MSG=" $CALLER_FILE:$CALLER_LINE    $2"

  case "$1" in
  debug)
    echo -e "$TIMESTAMP  \033[36mDEBUG\033[0m $MSG"
    ;;
  info)
    echo -e "$TIMESTAMP  \033[32mINFO \033[0m $MSG"
    ;;
  warn)
    echo -e "$TIMESTAMP  \033[33mWARN \033[0m $MSG"
    ;;
  error)
    echo -e "$TIMESTAMP  \033[31mERROR\033[0m $MSG"
    ;;
  *) ;;
  esac
}

# ubuntu
# download url: https://releases.hashicorp.com/terraform/1.9.8
install() {
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install terraform
}

install_offline() {
  logger info "install offline"

  terraform -v && {
    logger warn "terraform is already exist, the installation was aborted"
    return 0
  }

  logger info "terraform is not exist"

  if [ -e "$BACKUP_PACKAGE" ]; then
    tar -xzvf "$BACKUP_PACKAGE" -C /usr/local/bin/
  else
    logger info "terraform package not exit, please download first"
    return 1
  fi

  terraform -v && logger info "install successfully"
  tf -v || {
    echo "alias tf='terraform'" >>~/.bashrc
    source ~/.bashrc
  }
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

uninstall() {
  logger info "uninstall"
  read_uninstall_answer || exit 1
  sudo apt remove terraform
  logger info "uninstall successfully"
}

uninstall_offline() {
  logger info "uninstall offline"
  read_uninstall_answer || exit 1
  sudo rm -rf /usr/local/bin/terraform
  logger info "uninstall offline successfully"
}

main() {
  [ "$#" -gt 0 ] || (usage >&2 && exit 2)

  case "$1" in
  install)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    install
    ;;
  install_offline)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    install_offline
    ;;
  uninstall)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    uninstall
    ;;
  uninstall_offline)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    uninstall_offline
    ;;
  download)
    [ "$#" -ge 1 ] || (usage >&2 && exit 2)
    logger error "// TODO"
    download
    ;;
  *)
    usage && exit 0
    ;;
  esac
}

main "$@"
