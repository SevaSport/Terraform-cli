#!/bin/bash

# Форматирование вывода в терминале: цвета, заголовки, строки «метка … значение», шаги.

# Переменные ANSI для цвета текста (второй и последующие аргументы у форматтеров ниже): NC, RED, GREEN, YELLOW, BLUE, CYAN и др.
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

# Ширина «колонки» для точек между частями строки (вёрстка).
MESSAGE_WIDTH=60

# Максимальная длина фрагмента текста в заголовке и в левой/правой колонке строки-сообщения; длиннее — «...».
MESSAGE_MAX_TEXT=60

# Обрезать строку до MESSAGE_MAX_TEXT символов, добавляя «...» при переполнении.
# Параметры: $1 — исходная строка. Возврат: строка на stdout.
_clamp_message_text() {
    local s="$1"
    local max="${MESSAGE_MAX_TEXT:-60}"
    if ((${#s} > max)); then
        printf '%s' "${s:0:$((max - 3))}..."
    else
        printf '%s' "$s"
    fi
}

# Напечатать заголовок блока: цветной текст слева и заполнение точками до фиксированной ширины.
# Параметры: $1 — текст заголовка; $2 — код цвета (переменная ANSI). Возврат: печать в stdout, завершающий перевод строки перед заголовком.
title() {
    local left_text
    left_text=$(_clamp_message_text "$1")
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

# Одна строка в две колонки: метка слева, значение справа, между ними точки до края строки.
# Параметры: $1 — левая колонка; $2 — правая; $3 — цвет левой; $4 — цвет правой. Возврат: одна строка на stdout.
message() {
    local left_text=$(_clamp_message_text "$1")
    local right_text=$(_clamp_message_text "$2")
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

# Начать строку пошагового отчёта: только цветной текст слева (точки и итог дописываются отдельным вызовом ниже).
# Параметры: $1 — описание шага; $2 — цвет. Возврат: частичная строка на stdout; побочный эффект — export SAVED_LEFT_TEXT, SAVED_LEFT_COLOR.
step_name() {
    local left_text="$1"
    local left_color="$2"

    # Сохраняем левую часть в глобальной переменной для дальнейшего использования
    export SAVED_LEFT_TEXT="$left_text"
    export SAVED_LEFT_COLOR="$left_color"

    # Немедленный вывод левой части без точек
    printf "%b%s%b" "$left_color" "$left_text" "$NC"
}

# Завершить строку шага: точки от предыдущей левой части до статуса и цветной статус справа.
# Параметры: $1 — текст статуса (например «ОК»); $2 — цвет статуса. Читает SAVED_LEFT_TEXT (и SAVED_LEFT_COLOR). Возврат: окончание строки на stdout.
step_status() {
    local right_text="$1"
    local right_color="$2"

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

# Вывести абсолютные пути (например к логам), каждый с новой строки — чтобы в терминале IDE по ним можно было перейти.
# Параметры: произвольное число путей ($@). Возврат: 0; при отсутствии аргументов — ничего не печатает.
print_log_file_paths() {
    [[ $# -eq 0 ]] && return 0
    printf '%s\n' "$@"
}

# Стереть указанное число последних строк в терминале (убрать хвост после интерактивных запросов).
# Параметры: $1 — сколько строк очистить. Возврат: управляющие последовательности в stdout.
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