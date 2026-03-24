#!/bin/bash

# Проверка на стороне VPS: дистрибутив должен быть Ubuntu, версия не
# ниже минимальной из spec.md (сейчас Ubuntu 20+).

title "Проверка операционной системы на VPS" "$BLUE"

if ! run_ssh 'test -f /etc/os-release'; then
    message "Файл описания ОС на VPS" "не найден" "$RED" "$RED"
    exit 1
fi

if ! run_ssh 'grep -q "^ID=ubuntu$" /etc/os-release 2>/dev/null'; then
    message "Дистрибутив на VPS" "нужен Ubuntu" "$RED" "$RED"
    exit 1
fi

# Сравнение VERSION_ID с порогом 20.04 через sort -V.
VID=$(run_ssh '. /etc/os-release 2>/dev/null && echo "$VERSION_ID"')
VID=$(echo "$VID" | tr -d '\r\n' | head -n1)
max_ver=$(printf '%s\n' "${VID:-0}" "20.04" | sort -V | tail -n1)
if [[ "$max_ver" != "$VID" ]]; then
    message "Минимальная версия Ubuntu 20.04+" "сейчас ${VID:-?}" "$RED" "$RED"
    exit 1
fi

message "Версия Ubuntu на сервере" "$VID" "$YELLOW" "$GREEN"
