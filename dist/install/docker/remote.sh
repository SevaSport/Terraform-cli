#!/bin/bash

# Выполняется на VPS: установка Docker Engine через официальный apt-репозиторий.
# _sudo — из преамбулы ssh.sh.
set -e
type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

_sudo apt-get -qq update >/dev/null
_sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install ca-certificates curl >/dev/null

_sudo install -m 0755 -d /etc/apt/keyrings
_sudo curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
_sudo chmod a+r /etc/apt/keyrings/docker.asc

ubuntu_codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
repo_arch="$(dpkg --print-architecture)"
_sudo bash -c "echo \"deb [arch=${repo_arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${ubuntu_codename} stable\" > /etc/apt/sources.list.d/docker.list"

_sudo apt-get -qq update >/dev/null
_sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin >/dev/null
