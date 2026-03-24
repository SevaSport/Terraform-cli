#!/bin/bash

# apt update / upgrade / autoremove на VPS (remote.sh).
# Если появился reboot-required — перезагрузка и ожидание SSH.

check_reboot_required() {
    run_ssh "[ -f /var/run/reboot-required ]" && return 0
    run_ssh "command -v needs-restarting >/dev/null && needs-restarting -r 2>/dev/null | grep -q 'Reboot is required'" && return 0
    return 1
}

reboot_remote() {
    local reboot_wait_time="${1:-5}"
    local reboot_log="$LOGS_DIR/install-update-reboot.log"
    step_name "Перезагрузка VPS и ожидание SSH" "$YELLOW"

    printf '========== %s  %s ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "remote reboot" >>"$reboot_log"
    if run_ssh "sudo shutdown -r now" >>"$reboot_log" 2>&1; then
        step_status "запущена" "$GREEN"
        sleep "$reboot_wait_time"
        if ! wait_for_reboot "$reboot_wait_time"; then
            exit 1
        fi
        return 0
    else
        step_status "ошибка" "$RED"
        print_log_file_paths "$reboot_log"
        return 1
    fi
}

wait_for_reboot() {
    local reboot_wait_time="${1:-5}"
    local max_attempts
    max_attempts=$(ssh_reconnect_attempts)
    local attempt=1

    message "Ожидание ответа после перезагрузки" "восстановления связи" "$YELLOW" "$CYAN"

    while [ "$attempt" -le "$max_attempts" ]; do
        if run_ssh "true" >/dev/null 2>&1; then
            message "Сервер снова доступен по SSH" "Да" "$YELLOW" "$GREEN"
            return 0
        fi

        message "Повтор подключения SSH ($attempt/$max_attempts)" "нет ответа" "$YELLOW" "$CYAN"
        sleep "$reboot_wait_time"
        attempt=$((attempt + 1))
    done

    message "Сервер не ответил после перезагрузки" "Ошибка" "$RED" "$RED"
    return 1
}

update_packages() {
    local reboot_wait_time=5
    step_name "Обновление пакетов (apt)" "$YELLOW"

    run_ssh_with_file "$(dirname "$BASH_SOURCE")/remote.sh"
    local result=$?

    if [ "$result" -eq 0 ]; then
        step_status "ОК" "$GREEN"

        step_name "Проверка необходимости перезагрузки VPS" "$YELLOW"
        if check_reboot_required; then
            step_status "Да" "$YELLOW"
            reboot_remote "$reboot_wait_time"
        else
            step_status "Нет" "$GREEN"
        fi
    else
        step_status "ошибка (код: $result)" "$RED"
        print_last_remote_script_log_path
    fi

    return "$result"
}

update_packages
