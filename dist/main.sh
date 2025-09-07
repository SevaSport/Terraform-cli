#!/bin/bash

# Определение ОС
source $CHECK_SCRIPTS/local-os.sh

# Проверка и установка необходмых программ
source $CHECK_SCRIPTS/local-packages.sh

# Данные для соединения
VPS_IP=$(yq e '.vps.ip' $CREDENTIALS)
VPS_PORT=$(yq e '.vps.port' $CREDENTIALS)
VPS_USER=$(yq e '.vps.user' $CREDENTIALS)
VPS_PASS=$(yq e '.vps.pass' $CREDENTIALS)

#----------
# Проверка заполнения данных для подключения к виртуальной машине
source $VALIDATE_SCRIPTS/ssh-config.sh

#----------
# Проверка, что на локальной машине есть ssh-клиент и ssh-ключ
source $CHECK_SCRIPTS/local-ssh-key.sh

#----------
# Копирование локального ключа на удаленную машину, для правильной работы скрипта
# В процессе дальнейшей настройки root пользователь будет отключен для ssh подключения
source $CHECK_SCRIPTS/ssh-connection.sh

#----------
title "Выполенение команд на сервере" "$BLUE"
# Отключение IPv6, если в конфиге это указано
source $SETUP_SCRIPTS/ipv6-switch/local-shell.sh
# Обновление библиотек
source $INSTALL_SCRIPTS/update/local-shell.sh

#----------
# Установка дополнительных пакетов
source $INSTALL_SCRIPTS/packages/local-shell.sh

#----------
# Установка приложений

# Добавление пользователей
source $SETUP_SCRIPTS/users/add.sh

# Настройка ssh-сервера

# Установка и настройка fail2ban

# Установка и настройка ufw


# Установка Docker
source $INSTALL_SCRIPTS/docker/local-shell.sh

# Установка OpenVPN
# source $INSTALL_SCRIPTS/openvpn/local-shell.sh

# Установка Outline
source $INSTALL_SCRIPTS/outline/local-shell.sh


exit 0


# # Настройка SSH (изменение порта)
# SSH_PORT=$(yq e '.vps.applications.specific.ssh.port' $CONFIG_FILE)
# echo -e "${YELLOW}Настройка SSH порта на $SSH_PORT...${NC}"
# if sudo sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config && sudo systemctl restart sshd; then
#     echo -e "${GREEN}SSH успешно настроен на порт $SSH_PORT и перезапущен.${NC}"
# else
#     echo -e "${RED}Ошибка при настройке или перезапуске SSH.${NC}"
# fi

# # Настройка ufw (брандмауэра)
# echo -e "${YELLOW}Настройка UFW (брандмауэра)...${NC}"
# sudo ufw allow $SSH_PORT/tcp
# sudo ufw allow $OPENVPN_PORT/udp
# sudo ufw allow $OUTLINE_PORT/tcp
# if sudo ufw enable; then
#     echo -e "${GREEN}UFW успешно настроен.${NC}"
# else
#     echo -e "${RED}Ошибка при настройке UFW.${NC}"
# fi
