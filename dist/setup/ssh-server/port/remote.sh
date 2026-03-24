#!/bin/bash
# Смена порта SSH на VPS.
#
# Почему два шага:
# 1) sshd — файл 00-listen-port.conf в sshd_config.d (раньше 50-cloud-init: первое Port в конфиге побеждает).
# 2) Ubuntu 22.10+ — socket activation: без override у ssh.socket слушают старый ListenStream (часто 22).
#
# Проще «в голове»: отключить ssh.socket и включить только ssh.service — тогда порт только из sshd.
# Мы не делаем так по умолчанию, чтобы не менять модель запуска пакета; при желании: systemctl disable --now ssh.socket && systemctl enable ssh
#
# _sudo — из dist/libs/ssh.sh (_remote_stream_sudo_header).
set -euo pipefail

type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

NEW_PORT="${NEW_PORT:?NEW_PORT is required}"
SSH_IPV6_DISABLED="${SSH_IPV6_DISABLED:-0}"
PORT_DROPIN="/etc/ssh/sshd_config.d/00-listen-port.conf"
SOCKET_OVERRIDE="/etc/systemd/system/ssh.socket.d/override.conf"

_sudo mkdir -p /etc/ssh/sshd_config.d
_sudo bash -c "printf '%s\n' '# Порт SSH (drop-in)' 'Port ${NEW_PORT}' > '$PORT_DROPIN'"

UNIT_SOCKET=/lib/systemd/system/ssh.socket
[ -f "$UNIT_SOCKET" ] || UNIT_SOCKET=/usr/lib/systemd/system/ssh.socket
if [ -f "$UNIT_SOCKET" ]; then
    _sudo mkdir -p /etc/systemd/system/ssh.socket.d
    if [ "$SSH_IPV6_DISABLED" = "1" ]; then
        _sudo bash -c "printf '%s\n' \
            '[Socket]' \
            'ListenStream=' \
            'ListenStream=0.0.0.0:${NEW_PORT}' \
            > '$SOCKET_OVERRIDE'"
    else
        _sudo bash -c "printf '%s\n' \
            '[Socket]' \
            'ListenStream=' \
            'ListenStream=0.0.0.0:${NEW_PORT}' \
            'ListenStream=[::]:${NEW_PORT}' \
            > '$SOCKET_OVERRIDE'"
    fi
    _sudo systemctl daemon-reload
fi

_sudo sshd -t

( sleep 2; _sudo systemctl try-restart ssh.socket 2>/dev/null || true; _sudo systemctl try-restart ssh ) </dev/null >/dev/null 2>&1 &

exit 0
