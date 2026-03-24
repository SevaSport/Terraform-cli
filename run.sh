#!/bin/bash

# Точка входа: подготовка каталогов и библиотек, затем сценарий настройки VPS (main.sh).
# Пользователь запускает только ./run.sh; пути к логам в выводе — абсолютные (клик в IDE).

#######################################
# Пути проекта (BASE_DIR, LOGS_DIR, DIST_DIR — для логов и source).
BASE_DIR=$(cd "$(dirname "$BASH_SOURCE")" && pwd)

LOGS_DIR="$BASE_DIR/logs"
DIST_DIR="$BASE_DIR/dist"

# Свежие логи на каждый запуск: старые удаляются, чтобы не путаться в прошлых прогонах.
# Вывод удалённых команд (SSH) пишется в logs/*.log — при ошибке скрипт покажет путь к файлу.
mkdir -p "$LOGS_DIR"
find "$LOGS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

LIBS_SCRIPTS="$DIST_DIR/libs"
CHECK_SCRIPTS="$DIST_DIR/check"
VALIDATE_SCRIPTS="$DIST_DIR/validate"
INSTALL_SCRIPTS="$DIST_DIR/install"
SETUP_SCRIPTS="$DIST_DIR/setup"

#######################################
# config.yml — что настраиваем на VPS; credentials.yml — как к нему подключиться.
CONFIGURATIONS="$BASE_DIR/config.yml"
CREDENTIALS="$BASE_DIR/credentials.yml"

#######################################
# shell-messages.sh — цветной вывод в терминале (заголовки, шаги, сообщения).
source $LIBS_SCRIPTS/shell-messages.sh
# vps-config.sh — какие приложения включены в config.yml, опциональный порт SSH из config.
source $LIBS_SCRIPTS/vps-config.sh
# ssh.sh — подключение к VPS; сценарии на сервере не засоряют консоль, пишут в logs/.
source $LIBS_SCRIPTS/ssh.sh

#######################################
# main.sh — по шагам: проверка вашего ПК, ключи, сервер, затем установка по config.yml.
source $DIST_DIR/main.sh
