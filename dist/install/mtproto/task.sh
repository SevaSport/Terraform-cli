#!/bin/bash

# MTProto-proxy в Docker (telegrammessenger/proxy). Нужны Docker на VPS и блок vps.applications.mtproto в config.yml.
# В консоль — только ссылка tg:// из лога (как JSON у Outline).

# Параметры: нет (LAST_REMOTE_SCRIPT_LOG). Возврат: 0.
print_mtproto_proxy_access_payload() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local payload=""

    [[ -n "$log_path" && -f "$log_path" ]] || {
        message "Ссылка tg://proxy" "нет файла лога" "$YELLOW" "$YELLOW"
        return 0
    }
    payload=$(grep -aEo 'tg://proxy[?][^[:space:]]+' "$log_path" 2>/dev/null | tail -n1 || true)
    if [[ -z "$payload" ]]; then
        message "Ссылка tg://proxy" "не найдена в логе; см. $log_path" "$YELLOW" "$YELLOW"
        return 0
    fi

    printf '\n%s\n\n' "$payload"
}

# Параметры: нет. Возврат: 0 если контейнер mtproto-proxy запущен.
check_mtproto_container() {
    run_ssh_bash "export MTPROTO_ACTION=check MTPROTO_CONTAINER_NAME=mtproto-proxy MTPROTO_HOST_PORT=1 MTPROTO_PUBLIC_HOST=127.0.0.1" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
}

# Параметры: нет. Возврат: код удалённого show.
load_mtproto_proxy_line() {
    local port image
    port=$(yq e '.vps.applications.mtproto.port // 443' "$CONFIGURATIONS")
    image=$(yq e '.vps.applications.mtproto.image // "telegrammessenger/proxy:latest"' "$CONFIGURATIONS")
    [[ "$image" == "null" ]] && image="telegrammessenger/proxy:latest"

    run_ssh_bash \
        "export MTPROTO_ACTION=show MTPROTO_CONTAINER_NAME=mtproto-proxy MTPROTO_IMAGE=${image} MTPROTO_HOST_PORT=${port} MTPROTO_PUBLIC_HOST=${VPS_IP}" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
}

# Параметры: нет. Возврат: код удалённого install.
install_mtproto() {
    local port image secret secret_q
    port=$(yq e '.vps.applications.mtproto.port // 443' "$CONFIGURATIONS")
    image=$(yq e '.vps.applications.mtproto.image // "telegrammessenger/proxy:latest"' "$CONFIGURATIONS")
    [[ "$image" == "null" ]] && image="telegrammessenger/proxy:latest"
    secret=$(yq e '(.vps.applications.mtproto.secret // "")' "$CONFIGURATIONS")
    [[ "$secret" == "null" ]] && secret=""
    secret_q=$(printf '%q' "$secret")

    step_name "Установка MTProto-proxy (Docker)" "$YELLOW"
    if run_ssh_bash \
        "export MTPROTO_ACTION=install MTPROTO_CONTAINER_NAME=mtproto-proxy MTPROTO_IMAGE=${image} MTPROTO_HOST_PORT=${port} MTPROTO_PUBLIC_HOST=${VPS_IP} MTPROTO_SECRET=${secret_q}" \
        "$(dirname "$BASH_SOURCE")/remote.sh"; then
        step_status "Выполнено" "$GREEN"
        print_mtproto_proxy_access_payload
    else
        local result=$?
        step_status "Ошибка ($result)" "$RED"
        print_last_remote_script_log_path
        return "$result"
    fi
    return 0
}

setup_mtproto() {
    title "Установка MTProto-proxy для Telegram" "$BLUE"

    step_name "Проверка: Docker установлен на сервере" "$YELLOW"
    if is_package_installed "docker"; then
        step_status "Да" "$GREEN"
    else
        step_status "Нет" "$RED"
        message "Для MTProto нужен Docker" "включите applications.docker в config.yml" "$YELLOW" "$RED"
        exit 1
    fi

    step_name "Проверка: контейнер MTProto-proxy запущен" "$YELLOW"
    if check_mtproto_container; then
        step_status "Да" "$GREEN"
        step_name "Получение ссылки MTProto (tg://)" "$YELLOW"
        if load_mtproto_proxy_line; then
            step_status "ОК" "$GREEN"
            print_mtproto_proxy_access_payload
        else
            step_status "Ошибка" "$RED"
            print_last_remote_script_log_path
        fi
    else
        step_status "Нет" "$YELLOW"
        install_mtproto
    fi
}

if config_application_enabled mtproto; then
    setup_mtproto
fi
