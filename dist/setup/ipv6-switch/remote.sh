#!/bin/bash

# Проверка наличия строки для отключения IPv6
if grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf; then
    exit 0
else
    # Добавление строки для отключения IPv6
    echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
    echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
    echo "net.ipv6.conf.lo.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf > /dev/null

    # Применяем изменения
    if sudo sysctl -p > /dev/null; then
        exit 0
    else
        exit 1
    fi
fi
