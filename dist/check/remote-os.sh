#!/bin/bash

# Сводка о VPS: Ubuntu не ниже spec.md (20.04+), затем CPU, ОЗУ, диск.

title "Сводка информации о VPS" "$BLUE"

# Очистить переводы строк и CR из однострочного ответа SSH.
# Параметры: $1 — сырой вывод. Возврат: первая непустая строка на stdout.
remote_one_line() {
    echo "${1:-}" | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n1
}

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
VID=$(remote_one_line "$VID")
PRETTY=$(run_ssh '. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"')
PRETTY=$(remote_one_line "$PRETTY")

max_ver=$(printf '%s\n' "${VID:-0}" "20.04" | sort -V | tail -n1)
if [[ "$max_ver" != "$VID" ]]; then
    message "Минимальная версия Ubuntu 20.04+" "сейчас ${VID:-?}" "$RED" "$RED"
    exit 1
fi

cpu_model=$(remote_one_line "$(run_ssh "lscpu 2>/dev/null | awk -F: '\$1==\"Model name\" {gsub(/^[ \\t]+/,\"\",\$2); print \$2; exit}'")")
if [[ -z "$cpu_model" ]]; then
    cpu_model=$(remote_one_line "$(run_ssh "awk -F: '/model name|Model/ {gsub(/^[ \\t]+/,\"\",\$2); print \$2; exit}' /proc/cpuinfo 2>/dev/null")")
fi

cores=$(remote_one_line "$(run_ssh 'nproc 2>/dev/null')")

ram_total=$(remote_one_line "$(run_ssh "LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/{print \$2}'")")

# Частота ОЗУ: только число из DMI; иначе «—».
ram_speed=$(remote_one_line "$(run_ssh 's=$(sudo -n dmidecode -t memory 2>/dev/null | grep -m1 "^[[:space:]]*Speed:" | sed "s/^[[:space:]]*Speed:[[:space:]]*//"); if [ -n "$s" ] && ! echo "$s" | grep -qi unknown; then n=$(echo "$s" | grep -oE "[0-9]+" | head -n1); [ -n "$n" ] && echo "$n" || echo "—"; else echo "—"; fi')")

# df -hP: занято / полный объём, без слова used.
disk_info=$(remote_one_line "$(run_ssh "df -hP / 2>/dev/null | awk 'NR==2 {printf \"%s/%s\", \$3, \$2}'")")

message "Версия операционной системы" "${PRETTY:-${VID:-—}}" "$YELLOW" "$CYAN"
message "Процессор" "${cpu_model:-—}" "$YELLOW" "$CYAN"
message "Число ядер (логических CPU)" "${cores:-—}" "$YELLOW" "$CYAN"
message "Оперативная память (общий объём)" "${ram_total:-—}" "$YELLOW" "$CYAN"
message "Частота ОЗУ (по данным DMI)" "${ram_speed:-—}" "$YELLOW" "$CYAN"
message "Место на диске / (использовано / всего)" "${disk_info:-—}" "$YELLOW" "$CYAN"
