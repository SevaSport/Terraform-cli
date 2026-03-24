#!/bin/bash
# Выполняется на VPS: установка ufw, политика по умолчанию, правила для SSH/VPN/Outline и принудительное включение брандмауэра.
# _sudo задаётся на стороне управляющей машины (ssh.sh).
set -euo pipefail
type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

_sudo apt update -qq
_sudo DEBIAN_FRONTEND=noninteractive apt install -y ufw

_sudo ufw default deny incoming
_sudo ufw default allow outgoing

# Повторные allow для одного порта не критичны (|| true в вызове)
allow_ssh_port() {
    local p="$1"
    [[ -z "$p" ]] && return 0
    _sudo ufw allow "${p}/tcp" comment 'SSH' || true
}

allow_ssh_port "${SSH_RULE_PORT_1:-}"
if [[ -n "${SSH_RULE_PORT_2:-}" && "${SSH_RULE_PORT_2}" != "${SSH_RULE_PORT_1:-}" ]]; then
    allow_ssh_port "${SSH_RULE_PORT_2}"
fi

if [[ -n "${OPENVPN_PORT:-}" ]]; then
    _sudo ufw allow "${OPENVPN_PORT}/udp" comment 'OpenVPN' || true
fi

if [[ -n "${OUTLINE_API_PORT:-}" ]]; then
    _sudo ufw allow "${OUTLINE_API_PORT}/tcp" comment 'Outline API' || true
fi

if [[ -n "${OUTLINE_KEYS_PORT:-}" ]]; then
    _sudo ufw allow "${OUTLINE_KEYS_PORT}/tcp" comment 'Outline keys' || true
fi

enable_ufw() {
    # stdin нельзя отдавать и паролю sudo, и ufw — оборачиваем в bash -c
    _sudo bash -c 'echo y | ufw --force enable'
}

enable_ufw
_sudo ufw status verbose
