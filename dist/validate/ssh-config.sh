#!/bin/bash

title "Проверка данных для соединения с удаленной машиной" "$BLUE"

##################
# Проверка параметров для подключения к удаленному серверу
##################
# IP
if [[ -z "$VPS_IP" || "$VPS_IP" == "****" ]]; then
    message "IP адрес" "Не указан" "$YELLOW" "$RED"
    title "Указать IP адрес VPS можно в файле config.yml!" "$BLUE"
    lines_to_clear=3

    while true; do
        read -r -p "Введите IP адрес VPS: " VPS_IP
        ((lines_to_clear++))
        if [[ -n "$VPS_IP" ]]; then
            # Простая проверка на формат IP (опционально)
            if [[ "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                break
            else
                message "IP адрес" "Неверный формат IP адреса." "$YELLOW" "$RED"
                ((lines_to_clear++))
            fi
        else
            message "IP адрес" "IP адрес не может быть пустым." "$YELLOW" "$RED"
            ((lines_to_clear++))
        fi
    done
    clear_lines $lines_to_clear
fi
message "IP адрес" "$VPS_IP" "$YELLOW" "$GREEN"

##################
# PORT
if [[ -z "$VPS_PORT" || "$VPS_PORT" == "****" ]]; then
    message "SSH порт" "Не указан" "$YELLOW" "$RED"
    title "Указать SSH порт можно в файле config.yml!" "$BLUE"
    lines_to_clear=3

    while true; do
        read -r -p "Введите порт подключения [1-65535]: " VPS_PORT
        ((lines_to_clear++))
        
        # Проверки
        if [[ -z "$VPS_PORT" ]]; then
            message "SSH порт" "не может быть пустым." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        if ! [[ "$VPS_PORT" =~ ^[0-9]+$ ]]; then
            message "SSH порт" "должен быть числом." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        if (( VPS_PORT < 1 || VPS_PORT > 65535 )); then
            message "SSH порт" "должен быть в диапазоне 1-65535." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        break
    done
    clear_lines $lines_to_clear
fi
message "SSH порт" "$VPS_PORT" "$YELLOW" "$GREEN"

##################
# Имя пользователя
if [[ -z "$VPS_USER" || "$VPS_USER" == "****" ]]; then
    message "Имя пользователя" "Не указано" "$YELLOW" "$RED"
    title "Указать имя пользователя можно в файле config.yml!" "$BLUE"
    lines_to_clear=3

    while true; do
        read -r -p "Введите имя пользователя: " VPS_USER
        ((lines_to_clear++))
        
        # Проверки
        if [[ -z "$VPS_USER" ]]; then
            message "Имя пользователя" "не может быть пустым." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        # Проверка что имя не начинается с цифры или дефиса
        if [[ "$VPS_USER" =~ ^[0-9] ]]; then
            message "Имя пользователя" "не может начинаться с цифры." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        if [[ "$VPS_USER" =~ ^- ]]; then
            message "Имя пользователя" "не может начинаться с дефиса." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        # Проверка длины имени пользователя
        if (( ${#VPS_USER} < 2 )); then
            message "Имя пользователя" "должно быть не короче 2 символов." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        if (( ${#VPS_USER} > 32 )); then
            message "Имя пользователя" "должно быть не длиннее 32 символов." "$YELLOW" "$RED"
            ((lines_to_clear++))
            continue
        fi
        
        # Проверка на допустимые символы (только буквы, цифры, дефисы, подчеркивания)
        if ! [[ "$VPS_USER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            message "Имя пользователя" "содержит недопустимые символы." "$YELLOW" "$RED"
            message "Разрешены: буквы, цифры, дефисы и подчеркивания" "" "$YELLOW" "$RED"
            ((lines_to_clear+=2))
            continue
        fi
        
        break
    done
    clear_lines $lines_to_clear
fi
message "Имя пользователя" "$VPS_USER" "$YELLOW" "$GREEN"

##################
# Пароль пользователя
if [[ -z "$VPS_PASS" || "$VPS_PASS" == "****" ]]; then
    message "Пароль" "Не указан" "$YELLOW" "$RED"
    lines_to_clear=2
    # Запрос пароля с помощью команды read, ввод скрыт
    read -sp "Введите пароль для пользователя ${VPS_USER}: " VPS_PASS
    echo

    clear_lines $lines_to_clear
fi
message "Пароль" "**********" "$YELLOW" "$GREEN"
lines_to_clear=0