#!/bin/bash

curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh

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