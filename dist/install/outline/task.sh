#!/bin/bash

# Модуль Outline на ПК: вызывает remote.sh на VPS через run_ssh_bash.
# Порты берутся из config.yml (vps.applications.outline.port). Нужен включённый блок applications.outline.

# Инициировать на VPS загрузку официального установщика Outline и показать в терминале шаг «Загрузка…» с результатом.
# Параметры: нет (путь к удалённому сценарию — рядом с этим task.sh). Возврат: код завершения удалённого запуска.
load_outline_installer() {
    run_ssh_bash "export OUTLINE_ACTION=download" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
    local result=$?
    step_name "Загрузка установщика Outline" "$YELLOW"
    if [ "$result" -eq 0 ]; then
        step_status "ОК" "$GREEN"
    else
        step_status "ошибка (код: $result)" "$RED"
        print_last_remote_script_log_path
    fi
    return "$result"
}

# Узнать с VPS, запущен ли контейнер с образом Outline (проверка по подстроке в имени образа).
# Параметры: нет. Возврат: 0 если контейнер найден в docker ps, иначе код ошибки удалённой проверки.
outline_container_running() {
    run_ssh_bash "export OUTLINE_ACTION=check OUTLINE_CONTAINER_PATTERN=outline" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
}

# Запросить на сервере поиск строки JSON доступа Outline; полный вывод попадёт в файл лога последнего SSH-запуска.
# Параметры: нет. Возврат: код удалённого сценария; побочный эффект — обновление LAST_REMOTE_SCRIPT_LOG.
load_outline_access_payload() {
    run_ssh_bash "export OUTLINE_ACTION=payload" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
    return $?
}

# Достать из последнего лога SSH валидную строку JSON доступа и вывести её в консоль с отступами (для копирования в Outline Manager).
# Параметры: нет (читает LAST_REMOTE_SCRIPT_LOG). Возврат: 0; при отсутствии лога или JSON — предупреждение через message, без ненулевого кода.
print_outline_access_payload() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local payload=""

    [[ -n "$log_path" && -f "$log_path" ]] || {
        message "Outline access JSON" "нет файла лога" "$YELLOW" "$YELLOW"
        return 0
    }
    payload=$(
        grep -aEo '\{"apiUrl":"https://[^"]+","certSha256":"[A-Fa-f0-9]{64}"\}|\{"certSha256":"[A-Fa-f0-9]{64}","apiUrl":"https://[^"]+"\}|\{"apiUrl":"http://[^"]+","certSha256":"[A-Fa-f0-9]{64}"\}|\{"certSha256":"[A-Fa-f0-9]{64}","apiUrl":"http://[^"]+"\}' "$log_path" 2>/dev/null | tail -n1 || true
    )
    if [[ -z "$payload" ]]; then
        message "Outline access JSON" "не найден в логе; см. $log_path" "$YELLOW" "$YELLOW"
        return 0
    fi

    printf '\n%s\n\n' "$payload"
}

# Установить Outline на VPS с портами api/keys из config.yml и по успеху показать пользователю JSON доступа из лога.
# Параметры: нет (читает CONFIGURATIONS). Возврат: 0 при успехе; при ошибке установки — код ошибки и путь к логу.
install_outline() {
    message "Запуск установщика Outline на сервере" "выполняется" "$YELLOW" "$GREEN"

    local outline_api_port
    local outline_keys_port
    outline_api_port=$(yq e '.vps.applications.outline.port.api' "$CONFIGURATIONS")
    outline_keys_port=$(yq e '.vps.applications.outline.port.keys' "$CONFIGURATIONS")

    step_name "Установка VPN-сервера Outline" "$YELLOW"
    if run_ssh_bash \
        "export OUTLINE_ACTION=install OUTLINE_API_PORT=$outline_api_port OUTLINE_KEYS_PORT=$outline_keys_port" \
        "$(dirname "$BASH_SOURCE")/remote.sh"; then
        step_status "Выполнено" "$GREEN"
        print_outline_access_payload
    else
        local result=$? 
        step_status "Ошибка ($result)" "$RED"
        print_last_remote_script_log_path
        return "$result"
    fi
    return 0
}

# Проверить готовность: на сервере установлен пакет Docker и уже крутится контейнер Outline.
# Параметры: нет. Возврат: 0 если оба условия выполнены; 1 если нет Docker или нет контейнера (с поясняющим message).
check_outline_requirements() {
    if ! is_package_installed "docker"; then
        message "Для Outline нужен Docker на сервере" "не установлен" "$YELLOW" "$YELLOW"
        return 1
    fi

    if ! outline_container_running; then
        message "Контейнер Outline на сервере" "не найден" "$YELLOW" "$YELLOW"
        return 1
    fi

    return 0
}

# Главная ветка модуля: при отсутствии сервера — загрузка установщика и установка; если уже работает — только запрос и печать JSON.
# Параметры: нет (читает CONFIGURATIONS; модуль подключается только если в config объявлен outline). Возврат: при критической ошибке загрузки — exit 1 процесса.
setup_outline() {
    title "Установка VPN-сервера Outline" "$BLUE"

    if ! check_outline_requirements; then
        if load_outline_installer; then
            install_outline
        else
            message "Загрузка установщика Outline" "Ошибка" "$RED" "$RED"
            exit 1
        fi
    else
        message "VPN-сервер Outline на сервере" "уже работает" "$YELLOW" "$GREEN"
        load_outline_access_payload || true
        print_outline_access_payload
    fi
}

if config_application_enabled outline; then
    setup_outline
fi
