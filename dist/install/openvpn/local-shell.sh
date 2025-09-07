#!/bin/bash

# Проверяем, существует ли ключ 'applications.openvpn'
if yq eval '.vps.applications | has("openvpn")' "$CONFIGURATIONS" > /dev/null 2>&1; then
    title "Установка Openvpn" "$BLUE"

    # Проверка что Openvpn установлен на удаленной машине
    ssh -p $VPS_PORT "$VPS_USER@$VPS_IP" "dpkg -l | grep openvpn 2>/dev/null"
fi
