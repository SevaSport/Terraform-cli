#!/bin/bash

title "Настройка подключения к серверу" "$BLUE"

# Добавление публичного ключа на удаленную машину
sshpass -p "$VPS_PASS" ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -p $VPS_PORT "$VPS_USER@$VPS_IP" \
    > "$LOGS_DIR/ssh-key-copy.log" \
    2> "$LOGS_DIR/ssh-key-copy-error.log"
if [ ! $? -eq 0 ]; then
    sshpass -p "$VPS_PASS" ssh-copy-id -p $VPS_PORT "$VPS_USER@$VPS_IP" \
        >> "$LOGS_DIR/ssh-key-copy.log" \
        2>> "$LOGS_DIR/ssh-key-copy-error.log"
fi

if [ $? -eq 0 ]; then
    message "Копирование публичного ключа на сервер" "OK" "$YELLOW" "$GREEN"
else
    message "Копирование публичного ключа на сервер" "Ошибка" "$YELLOW" "$RED"
    exit 1
fi

# Подключение к удаленной машине по ключу
if ssh -q -o ConnectTimeout=5 -o BatchMode=yes -p $VPS_PORT "$VPS_USER@$VPS_IP" exit; then
    message "Проверка авторизации по ssh-ключу" "OK" "$YELLOW" "$GREEN"
else
    message "Проверка авторизации по ssh-ключу" "Ошибка" "$YELLOW" "$RED"
    exit 1
fi