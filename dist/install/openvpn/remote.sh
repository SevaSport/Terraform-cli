#!/bin/bash
# Выполняется на VPS: неинтерактивная установка OpenVPN через angristan/openvpn-install (если сервер ещё не развёрнут).
set -euo pipefail

OPENVPN_PORT="${OPENVPN_PORT:?}"

cd /tmp
if [[ -e /etc/openvpn/server/server.conf ]]; then
    echo "OpenVPN already configured"
    exit 0
fi

curl -fsSL -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

export AUTO_INSTALL=y
export APPROVE_INSTALL=y
export APPROVE_IP=y
export IPV6_SUPPORT=n
export PORT_CHOICE=2 # Порт по умолчания 1194
export DNS=11 # AdGuard DNS (Anycast: worldwide)
export PROTOCOL_CHOICE=2 # 1 UDP, 2 TCP
export COMPRESSION_ENABLED=n
export CUSTOMIZE_ENC=n
export CLIENT=openvpn_client
export PASS=1

./openvpn-install.sh
