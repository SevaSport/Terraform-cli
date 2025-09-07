#!/bin/bash

REBOOT_WAIT_TIME=5

# Функция проверки необходимости перезагрузки
check_reboot_required() {
    run_ssh "[ -f /var/run/reboot-required ]" && return 0
    run_ssh "command -v needs-restarting >/dev/null && needs-restarting -r 2>/dev/null | grep -q 'Reboot is required'" && return 0
    return 1
}

# Функция перезагрузки удаленной машины
reboot_remote() {
    step_name "Перезагрузка сервера" "$YELLOW"
    
    # Отправляем команду перезагрузки
    if run_ssh "sudo shutdown -r now"; then
        step_status "запущена" "$GREEN"
        
        # Ждем немного перед проверкой доступности
        sleep $REBOOT_WAIT_TIME
        
        # Ожидаем восстановления связи
        if ! wait_for_reboot; then
            exit 1  # Останавливаем выполнение если reboot failed
        fi
        return 0
    else
        step_status "ошибка" "$RED"
        return 1
    fi
}

# Функция ожидания перезагрузки
wait_for_reboot() {
    local max_attempts=10
    local attempt=1
    
    message "Ожидание сервера" "восстановления связи" "$YELLOW" "$CYAN"
    
    while [ $attempt -le $max_attempts ]; do
        if run_ssh "true" >/dev/null 2>&1; then
            message "Сервер перезагружен" "да" "$YELLOW" "$GREEN"
            return 0
        fi
        
        message "Попытка соединения $attempt/$max_attempts" "сервер недоступен" "$YELLOW" "$CYAN"
        sleep $REBOOT_WAIT_TIME
        ((attempt++))
    done
    
    message "Ошибка" "сервер не ответил после перезагрузки" "$RED" "$RED"
    return 1
}

# Обновление библиотек
update_packages() {
    step_name "Обновление пакетов" "$YELLOW"
    
    # Сохраняем логи в файлы
    run_ssh_with_file "$(dirname "$BASH_SOURCE")/remote.sh" \
        1>> "$LOGS_DIR/repo-install.log" \
        2>> "$LOGS_DIR/repo-error.log"
    
    local result=$?

    if [ $result -eq 0 ]; then
        step_status "ОК" "$GREEN"

        # Проверяем необходимость перезагрузки
        if check_reboot_required; then
            message "Требуется перезагрузка сервера" "да" "$YELLOW" "$YELLOW"
            reboot_remote
        else
            message "Требуется перезагрузка сервера" "нет" "$YELLOW" "$GREEN"
        fi
    else
        step_status "ошибка (код: $result)" "$RED"
    fi
    
    
    return $result
}

update_packages
