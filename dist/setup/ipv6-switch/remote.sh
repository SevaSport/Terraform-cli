#!/bin/bash

# Выполняется на VPS: если IPv6 ещё не отключён в sysctl.conf — дописываем параметры и применяем sysctl -p.
set -euo pipefail
type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }
type _sudo_tee_file >/dev/null 2>&1 || _sudo_tee_file() { sudo tee "$1" >/dev/null; }

# Проверка наличия строки для отключения IPv6
if grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf; then
    exit 0
else
    # Добавление строки для отключения IPv6
    _sudo sh -c "printf '%s\n' 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf"
    _sudo sh -c "printf '%s\n' 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf"
    _sudo sh -c "printf '%s\n' 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf"

    # Применяем изменения
    if _sudo sysctl -p > /dev/null; then
        exit 0
    else
        exit 1
    fi
fi
