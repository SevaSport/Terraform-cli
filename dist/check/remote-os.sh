#!/bin/bash

# Сводка о VPS: Ubuntu не ниже spec.md (20.04+), затем CPU, ОЗУ, диск.

# Очистить переводы строк и CR из однострочного ответа SSH.
# Параметры: $1 — сырой вывод. Возврат: первая непустая строка на stdout.
remote_one_line() {
    echo "${1:-}" | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n1
}

check_os_release_file() {
    if ! run_ssh 'test -f /etc/os-release' >/dev/null 2>&1; then
        message "Файл описания ОС на VPS" "не найден (шаг пропущен)" "$YELLOW" "$YELLOW"
        return 1
    fi
    return 0
}

check_ubuntu_id() {
    if ! run_ssh 'grep -q "^ID=ubuntu$" /etc/os-release 2>/dev/null' >/dev/null 2>&1; then
        message "Дистрибутив на VPS" "не Ubuntu (шаг пропущен)" "$YELLOW" "$YELLOW"
        return 1
    fi
    return 0
}

print_os_info() {
    local os_release_ok="$1" ubuntu_id_ok="$2"
    local vid pretty max_ver

    if [[ "$os_release_ok" -ne 1 ]]; then
        message "Версия операционной системы" "шаг пропущен" "$YELLOW" "$YELLOW"
        return
    fi

    vid=$(remote_one_line "$(run_ssh '. /etc/os-release 2>/dev/null && echo "$VERSION_ID"')")
    pretty=$(remote_one_line "$(run_ssh '. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"')")

    if [[ "$ubuntu_id_ok" -eq 1 ]]; then
        max_ver=$(printf '%s\n' "${vid:-0}" "20.04" | sort -V | tail -n1)
        if [[ "$max_ver" != "$vid" ]]; then
            message "Минимальная версия Ubuntu 20.04+" "сейчас ${vid:-?}" "$RED" "$RED"
            exit 1
        fi
    fi

    message "Версия операционной системы" "${pretty:-${vid:-—}}" "$YELLOW" "$CYAN"
}

print_cpu_info() {
    local cpu_model cores cpu_sysbench
    cpu_model=$(remote_one_line "$(run_ssh "lscpu 2>/dev/null | awk -F: '\$1==\"Model name\" {gsub(/^[ \\t]+/,\"\",\$2); print \$2; exit}'")")
    if [[ -z "$cpu_model" ]]; then
        cpu_model=$(remote_one_line "$(run_ssh "awk -F: '/model name|Model/ {gsub(/^[ \\t]+/,\"\",\$2); print \$2; exit}' /proc/cpuinfo 2>/dev/null")")
    fi
    cores=$(remote_one_line "$(run_ssh 'nproc 2>/dev/null')")

    message "Процессор (CPU)" "${cpu_model:-—}" "$YELLOW" "$CYAN"
    message "Число ядер (логических CPU)" "${cores:-—}" "$YELLOW" "$CYAN"

    cpu_sysbench=$(remote_one_line "$(run_ssh "if command -v sysbench >/dev/null 2>&1; then sysbench cpu --threads=1 --time=5 run 2>/dev/null | sed -n 's/^[[:space:]]*events per second:[[:space:]]*//p' | head -n1; else echo '—'; fi")")
    [[ -z "$cpu_sysbench" ]] && cpu_sysbench="—"
    message "Производительность CPU (sysbench)" "${cpu_sysbench}" "$YELLOW" "$CYAN"
}

print_ram_info() {
    local ram_total ram_speed ram_read_test ram_write_test
    ram_total=$(remote_one_line "$(run_ssh "LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/{print \$2}'")")
    ram_speed=$(remote_one_line "$(run_ssh 's=$(sudo -n dmidecode -t memory 2>/dev/null | grep -m1 "^[[:space:]]*Speed:" | sed "s/^[[:space:]]*Speed:[[:space:]]*//"); if [ -n "$s" ] && ! echo "$s" | grep -qi unknown; then n=$(echo "$s" | grep -oE "[0-9]+" | head -n1); [ -n "$n" ] && echo "$n" || echo "—"; else echo "—"; fi')")

    message "Оперативная память (общий объём)" "${ram_total:-—}" "$YELLOW" "$CYAN"
    message "Частота RAM (по данным DMI)" "${ram_speed:-—}" "$YELLOW" "$CYAN"

    ram_read_test=$(remote_one_line "$(run_ssh "if command -v sysbench >/dev/null 2>&1; then out=\$(sysbench memory --memory-block-size=8M --memory-total-size=256M --memory-oper=read run 2>/dev/null); v=\$(printf '%s\n' \"\$out\" | awk -F'[()]' '/transferred/ && NF>=2 {gsub(/^[ \t]+|[ \t]+$/, \"\", \$2); print \$2; exit}'); [ -z \"\$v\" ] && v=\$(printf '%s\n' \"\$out\" | sed -n 's/^[[:space:]]*\\([0-9.][0-9.]* [kMGT]*i\{0,1\}B\\/sec\\).*/\\1/p' | head -n1); [ -z \"\$v\" ] && v=\$(printf '%s\n' \"\$out\" | sed -n 's/^[[:space:]]*\\([0-9.][0-9.]* [kMGT]*i\{0,1\}B\\/s\\).*/\\1/p' | head -n1); [ -n \"\$v\" ] && echo \"\$v\" || echo '—'; else echo '—'; fi")")
    if [[ -z "$ram_read_test" || "$ram_read_test" == "—" ]]; then
        ram_read_test=$(remote_one_line "$(run_ssh "f=/dev/shm/.ram_read_test.bin; dd if=/dev/zero of=\$f bs=1M count=64 conv=fdatasync >/dev/null 2>&1 || true; out=\$(dd if=\$f of=/dev/null bs=4M 2>&1 | sed -n 's/.*, *\\([0-9.][0-9.]* [kMGT]*i\{0,1\}B\\/s\\).*/\\1/p' | head -n1); rm -f \$f >/dev/null 2>&1 || true; [ -n \"\$out\" ] && echo \"\$out\" || echo '—'")")
    fi
    [[ -z "$ram_read_test" ]] && ram_read_test="—"
    message "Тест чтения (RAM read)" "${ram_read_test}" "$YELLOW" "$CYAN"

    ram_write_test=$(remote_one_line "$(run_ssh "if command -v sysbench >/dev/null 2>&1; then out=\$(sysbench memory --memory-block-size=8M --memory-total-size=256M --memory-oper=write run 2>/dev/null); v=\$(printf '%s\n' \"\$out\" | awk -F'[()]' '/transferred/ && NF>=2 {gsub(/^[ \t]+|[ \t]+$/, \"\", \$2); print \$2; exit}'); [ -z \"\$v\" ] && v=\$(printf '%s\n' \"\$out\" | sed -n 's/^[[:space:]]*\\([0-9.][0-9.]* [kMGT]*i\{0,1\}B\\/sec\\).*/\\1/p' | head -n1); [ -z \"\$v\" ] && v=\$(printf '%s\n' \"\$out\" | sed -n 's/^[[:space:]]*\\([0-9.][0-9.]* [kMGT]*i\{0,1\}B\\/s\\).*/\\1/p' | head -n1); [ -n \"\$v\" ] && echo \"\$v\" || echo '—'; else echo '—'; fi")")
    if [[ -z "$ram_write_test" || "$ram_write_test" == "—" ]]; then
        ram_write_test=$(remote_one_line "$(run_ssh "f=/dev/shm/.ram_write_test.bin; out=\$(dd if=/dev/zero of=\$f bs=4M count=64 conv=fdatasync 2>&1 | sed -n 's/.*, *\\([0-9.][0-9.]* [kMGT]*i\{0,1\}B\\/s\\).*/\\1/p' | head -n1); rm -f \$f >/dev/null 2>&1 || true; [ -n \"\$out\" ] && echo \"\$out\" || echo '—'")")
    fi
    [[ -z "$ram_write_test" ]] && ram_write_test="—"
    message "Тест записи (RAM write)" "${ram_write_test}" "$YELLOW" "$CYAN"
}

print_disk_info() {
    local disk_info disk_write_test disk_read_test
    disk_info=$(remote_one_line "$(run_ssh "df -hP / 2>/dev/null | awk 'NR==2 {printf \"%s/%s\", \$3, \$2}'")")
    message "Место на диске (использовано / всего)" "${disk_info:-—}" "$YELLOW" "$CYAN"

    disk_read_test=$(remote_one_line "$(run_ssh "f=/tmp/.vps_read_test.bin; dd if=/dev/zero of=\$f bs=1M count=64 conv=fdatasync >/dev/null 2>&1 || true; out=\$(dd if=\$f of=/dev/null bs=4M iflag=direct 2>&1 | sed -n 's/.*, *\\([0-9.][0-9.]* [kMGT]*B\\/s\\).*/\\1/p' | head -n1); rm -f \$f >/dev/null 2>&1 || true; [ -n \"\$out\" ] && echo \"\$out\" || echo '—'")")
    message "Тест SSD (чтение)" "${disk_read_test}" "$YELLOW" "$CYAN"

    disk_write_test=$(remote_one_line "$(run_ssh "f=/tmp/.vps_write_test.bin; out=\$(dd if=/dev/zero of=\$f bs=4M count=64 conv=fdatasync 2>&1 | sed -n 's/.*, *\\([0-9.][0-9.]* [kMGT]*B\\/s\\).*/\\1/p' | head -n1); rm -f \$f >/dev/null 2>&1 || true; [ -n \"\$out\" ] && echo \"\$out\" || echo '—'")")
    message "Тест SSD (запись)" "${disk_write_test}" "$YELLOW" "$CYAN"
}

print_network_info() {
    local speedtest_pair speedtest_download speedtest_upload
    speedtest_pair=$(remote_one_line "$(run_ssh 'if command -v speedtest-cli >/dev/null 2>&1; then out=$(speedtest-cli --secure --simple 2>/dev/null || speedtest-cli --simple 2>/dev/null || true); else out=""; fi; d=$(printf "%s\n" "$out" | sed -n "s/^Download:[[:space:]]*//p" | head -n1); u=$(printf "%s\n" "$out" | sed -n "s/^Upload:[[:space:]]*//p" | head -n1); [ -z "$d" ] && d="—"; [ -z "$u" ] && u="—"; printf "%s|%s" "$d" "$u"')")
    speedtest_download="${speedtest_pair%%|*}"
    speedtest_upload="${speedtest_pair#*|}"
    [[ -z "$speedtest_download" ]] && speedtest_download="—"
    [[ -z "$speedtest_upload" ]] && speedtest_upload="—"
    message "Тест сети (speedtest download)" "${speedtest_download}" "$YELLOW" "$CYAN"
    message "Тест сети (speedtest upload)" "${speedtest_upload}" "$YELLOW" "$CYAN"
}

main() {
    local os_release_ok=0
    local ubuntu_id_ok=0

    title "Сводка информации о VPS" "$BLUE"

    if check_os_release_file; then
        os_release_ok=1
    fi
    if [[ "$os_release_ok" -eq 1 ]] && check_ubuntu_id; then
        ubuntu_id_ok=1
    fi
    print_os_info "$os_release_ok" "$ubuntu_id_ok"

    print_cpu_info
    message "" "" "$YELLOW" "$CYAN"

    print_ram_info
    message "" "" "$YELLOW" "$CYAN"

    print_disk_info
    message "" "" "$YELLOW" "$CYAN"

    print_network_info
}

main
