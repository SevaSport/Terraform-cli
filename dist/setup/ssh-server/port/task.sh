#!/bin/bash

# Меняет порт sshd на значение из applications.ssh.port, если ключ задан
# и значение отличается от текущего VPS_PORT. Без ключа port — пропуск.
# Выполняется уже от пользователя ssh, после harden/task.sh.

setup_ssh_port() {
    local ssh_app_port
    local ipv6_disable_cfg
    local ssh_ipv6_disabled

    skip_unless_application ssh

    ssh_app_port=$(vps_ssh_application_port_optional)
    if [[ -z "$ssh_app_port" ]]; then
        message "Порт SSH-сервера" "не задан в applications.ssh — без изменений" "$YELLOW" "$GREEN"
        return 0 2>/dev/null || exit 0
    fi

    if [[ "$ssh_app_port" == "$VPS_PORT" ]]; then
        message "Порт SSH-сервера" "без изменений" "$YELLOW" "$GREEN"
        return 0 2>/dev/null || exit 0
    fi

    title "Изменение порта SSH-сервера" "$BLUE"

    # Читаем флаг из config (поддерживаем оба ключа: ipv6-disable и ipv6_disable)
    ipv6_disable_cfg=$(yq e '(.vps."ipv6-disable" // .vps.ipv6_disable // false)' "$CONFIGURATIONS")
    ssh_ipv6_disabled=0
    [[ "$ipv6_disable_cfg" == "true" ]] && ssh_ipv6_disabled=1

    if run_ssh_bash \
        "export NEW_PORT=$(printf '%q' "$ssh_app_port") SSH_IPV6_DISABLED=$ssh_ipv6_disabled" \
        "$SETUP_SCRIPTS/ssh-server/port/remote.sh"; then
        export VPS_PORT="$ssh_app_port"
        message "Новый порт для дальнейшего SSH" "$VPS_PORT" "$YELLOW" "$GREEN"
        message "Перезапуск SSH службы" "Ожидание" "$YELLOW" "$CYAN"
        if ! wait_for_ssh_after_sshd_port_change; then
            exit 1
        fi
    else
        message "Изменение порта SSH-сервера" "Ошибка" "$YELLOW" "$RED"
        print_last_remote_script_log_path
        exit 1
    fi
}

setup_ssh_port
