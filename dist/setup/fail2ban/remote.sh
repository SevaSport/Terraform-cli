#!/bin/bash
# Выполняется на VPS: пакет fail2ban, локальный jail sshd с указанным портом, enable и restart службы.
# _sudo / _sudo_tee_file — из преамбулы ssh.sh.
set -euo pipefail
type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }
type _sudo_tee_file >/dev/null 2>&1 || _sudo_tee_file() { sudo tee "$1" >/dev/null; }

SSH_PORT_FOR_JAIL="${SSH_PORT_FOR_JAIL:?}"

_sudo apt update -qq
_sudo DEBIAN_FRONTEND=noninteractive apt install -y fail2ban

_sudo_tee_file /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT_FOR_JAIL}
maxretry = 5
findtime = 10m
bantime = 1h
EOF

_sudo systemctl enable fail2ban
_sudo systemctl restart fail2ban
