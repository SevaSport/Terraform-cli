#!/bin/bash

#######################################
# Определение путей проекта
BASE_DIR=$(dirname "$BASH_SOURCE")

LOGS_DIR="$BASE_DIR/logs"
DIST_DIR="$BASE_DIR/dist"

LIBS_SCRIPTS="$DIST_DIR/libs"
CHECK_SCRIPTS="$DIST_DIR/check"
VALIDATE_SCRIPTS="$DIST_DIR/validate"
INSTALL_SCRIPTS="$DIST_DIR/install"
SETUP_SCRIPTS="$DIST_DIR/setup"

#######################################
# Чтение конфигурационного файла
CONFIGURATIONS="$BASE_DIR/config.yml"
CREDENTIALS="$BASE_DIR/credentials.yml"

#######################################
# Библиотеки цветов и 
#  форматирования сообщений в консоли
source $LIBS_SCRIPTS/shell-messages.sh
# Функции подключения по ssh, выполнения
#  команд и проверок
source $LIBS_SCRIPTS/ssh.sh

#######################################
# Запуск выполнения основного скрипта
source $DIST_DIR/main.sh