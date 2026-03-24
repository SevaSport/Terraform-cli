#!/bin/bash

# Выполняется на VPS: официальный скрипт установки Docker Engine (get.docker.com).
# _sudo — из преамбулы ssh.sh.
type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }
_sudo bash -c 'curl -fsSL https://get.docker.com -o get-docker.sh'
_sudo sh ./get-docker.sh
