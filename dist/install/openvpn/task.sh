#!/bin/bash

# Заготовка: при applications.openvpn полная установка будет здесь.
# Сейчас только проверка наличия пакета openvpn в dpkg на сервере.

setup_openvpn() {
    if config_application_enabled openvpn; then
        title "Установка и первичная настройка OpenVPN на VPS" "$BLUE"
        run_ssh "dpkg -l | grep openvpn 2>/dev/null"
    fi
}

setup_openvpn
