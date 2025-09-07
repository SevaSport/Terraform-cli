#!/bin/bash

# Цветовые переменные
# Базовые цвета
NC='\033[0m'           # Сброс цвета
BLACK='\033[0;30m'     # Чёрный
RED='\033[0;31m'       # Красный
GREEN='\033[0;32m'     # Зелёный
YELLOW='\033[0;33m'    # Жёлтый
BLUE='\033[0;34m'      # Синий
MAGENTA='\033[0;35m'   # Пурпурный
CYAN='\033[0;36m'      # Голубой
WHITE='\033[0;37m'     # Белый

# Яркие версии
BRIGHT_BLACK='\033[0;90m'    # Ярко-чёрный
BRIGHT_RED='\033[0;91m'      # Ярко-красный
BRIGHT_GREEN='\033[0;92m'    # Ярко-зелёный
BRIGHT_YELLOW='\033[0;93m'   # Ярко-жёлтый
BRIGHT_BLUE='\033[0;94m'     # Ярко-синий
BRIGHT_MAGENTA='\033[0;95m'  # Ярко-пурпурный
BRIGHT_CYAN='\033[0;96m'     # Ярко-голубой
BRIGHT_WHITE='\033[0;97m'    # Ярко-белый

# Ширина консоли
MESSAGE_WIDTH=60

title() {
    local left_text="$1"
    local left_color="$2"

    # Вычисляем ширину оставшегося пространства
    local left_length=${#left_text}
    local usable_width=$((MESSAGE_WIDTH - left_length - 2))  # 2 для отступа и точек

    # Создаем строку с точками
    local dots
    if [ $usable_width -gt 0 ]; then
        dots=$(printf "%-${usable_width}s" '' | tr ' ' '.')
    else
        dots=""
    fi

    # Формируем финальную строку
    echo
    printf "%b%s%b %s %b\n" "$left_color" "$left_text" "$NC" "$dots" "$NC"
}

# Функция для выводы сообщений
message() {
    local left_text="$1"
    local right_text="$2"
    local left_color="$3"
    local right_color="$4"

    # Вычисляем ширину оставшегося пространства
    local left_length=${#left_text}
    local right_length=${#right_text}
    local usable_width=$((MESSAGE_WIDTH - left_length - right_length - 3))  # 3 для отступа и точек

    # Создаем строку с точками
    local dots
    if [ $usable_width -gt 0 ]; then
        dots=$(printf "%-${usable_width}s" '' | tr ' ' '.')
    else
        dots=""
    fi

    # Формируем финальную строку
    printf "%b%s%b %s %b%s%b\n" "$left_color" "$left_text" "$NC" "$dots" "$right_color" "$right_text" "$NC"
}

# Функция для вывода левой части
step_name() {
    local left_text="$1"
    local left_color="$2"

    # Сохраняем левую часть в глобальной переменной для дальнейшего использования
    export SAVED_LEFT_TEXT="$left_text"
    export SAVED_LEFT_COLOR="$left_color"

    # Немедленный вывод левой части без точек
    printf "%b%s%b" "$left_color" "$left_text" "$NC"
}

# Функция для вывода правой части
step_status() {
    local right_text="$1"
    local right_color="$2"
    local total_width=60

    # Используем сохраненные данные из левой части
    local left_text="$SAVED_LEFT_TEXT"
    local left_color="$SAVED_LEFT_COLOR"

    # Вычисляем ширину оставшегося пространства
    local left_length=${#left_text}
    local right_length=${#right_text}
    local usable_width=$((MESSAGE_WIDTH - left_length - right_length - 3))  # 3 для отступа и точек

    # Создаем строку с точками
    local dots
    if [ $usable_width -gt 0 ]; then
        dots=$(printf "%-${usable_width}s" '' | tr ' ' '.')
    else
        dots=""
    fi

    # Выводим точки и правую часть
    printf " %s %b%s%b\n" "$dots" "$right_color" "$right_text" "$NC"
}

# Функция удаления строк в консоли
clear_lines() {
    local count=$1
    for ((i=0; i<count; i++)); do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            printf "\033[1A"  # Move up one line
            printf "\033[2K"  # Clear the line
        else
            # Linux и другие
            echo -e "\033[1A\033[2K"
        fi
    done
}