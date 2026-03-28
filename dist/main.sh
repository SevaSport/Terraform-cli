#!/bin/bash

# Сценарий после run.sh: сначала убеждаемся, что с вашего компьютера можно безопасно
# управлять VPS, затем по очереди применяем настройки из config.yml / credentials.yml.

#----------
# У вас подходящая ОС и установлены yq и sshpass (без них скрипт не запустится).
source $CHECK_SCRIPTS/local-os.sh

# При необходимости доустановит недостающие утилиты (Homebrew или apt).
source $CHECK_SCRIPTS/local-packages.sh

#----------
# Адрес и учётная запись VPS из credentials.yml (дальше — везде эти переменные).
VPS_IP=$(yq e '.vps.ip' $CREDENTIALS)
VPS_PORT=$(yq e '.vps.port' $CREDENTIALS)
VPS_USER=$(yq e '.vps.user' $CREDENTIALS)
VPS_PASS=$(yq e '.vps.pass' $CREDENTIALS)

#----------
# Если IP/порт/логин/пароль не заданы — скрипт спросит их в терминале.
source $VALIDATE_SCRIPTS/ssh-config.sh

#----------
# Проверка ssh и ключей; при отсутствии ключа — предложение создать.
source $CHECK_SCRIPTS/local-ssh-key.sh

#----------
# Копирование ключа на сервер и проверка входа без пароля (дальше работа идёт по ключу).
source $CHECK_SCRIPTS/ssh-connection.sh

#----------
# Проверка информации о VPS (Ubuntu 20+): ОС, CPU, ОЗУ, диск (см. remote-os.sh).
source $CHECK_SCRIPTS/remote-os.sh

#----------
# Дальше — изменения на самом сервере; порядок важен (сеть → SSH → фаервол → сервисы).
title "Выполнение команд на удалённом сервере" "$BLUE"

# Отключение IPv6 на сервере — только если задано в config.yml (иначе шаг пропускается внутри модуля).
source $SETUP_SCRIPTS/ipv6-switch/task.sh
# Обновление системы на VPS; при необходимости перезагрузка и ожидание.
source $INSTALL_SCRIPTS/update/task.sh

#----------
# Установка списка пакетов из config.yml (nano, ufw и т.д.).
source $INSTALL_SCRIPTS/packages/task.sh

#----------
# Создание пользователей, sudo, ключи в authorized_keys — как в config.yml.
source $SETUP_SCRIPTS/users/task.sh

# Настройки безопасности sshd, смена порта SSH при необходимости, фаервол и fail2ban.
source $SETUP_SCRIPTS/ssh-server/harden/task.sh
source $SETUP_SCRIPTS/ssh-server/port/task.sh
source $SETUP_SCRIPTS/ufw/task.sh
source $SETUP_SCRIPTS/fail2ban/task.sh

# Установка Docker, если задано в applications.docker
source $INSTALL_SCRIPTS/docker/task.sh

# Раскомментируйте, если в config.yml включён OpenVPN.
# source $INSTALL_SCRIPTS/openvpn/task.sh

# VPN Outline
source $INSTALL_SCRIPTS/outline/task.sh

# MTProto-proxy (Telegram)
source $INSTALL_SCRIPTS/mtproto/task.sh

exit 0
