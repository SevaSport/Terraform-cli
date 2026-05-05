#!/bin/bash

# Устанавливает fail2ban и jail для sshd. Порт в jail: applications.ssh.port
# при наличии, иначе текущий VPS_PORT (как в credentials после смены порта).

setup_fail2ban() {
    local ssh_port_for_jail

    skip_unless_application fail2ban

    if ! config_application_enabled ssh; then
        message "Fail2ban пропущен" "нет секции applications.ssh" "$YELLOW" "$YELLOW"
        return 0 2>/dev/null || exit 0
    fi

    ssh_port_for_jail=$(vps_ssh_application_port_optional)
    [[ -z "$ssh_port_for_jail" ]] && ssh_port_for_jail="$VPS_PORT"

    title "Настройка блокировщика (fail2ban)" "$BLUE"

    if run_ssh_bash \
        "export SSH_PORT_FOR_JAIL=$ssh_port_for_jail" \
        "$SETUP_SCRIPTS/fail2ban/remote.sh"; then
        message "Защита SSH от подбора пароля" "Выполнена" "$YELLOW" "$GREEN"
        message "Сервис Fail2ban" "Запущен" "$YELLOW" "$GREEN"
    else
        message "Установка и настройка fail2ban" "Ошибка" "$YELLOW" "$RED"
        print_last_remote_script_log_path
        message "Продолжение выполнения" "без fail2ban" "$RED" "$RED"
    fi
}

setup_fail2ban
