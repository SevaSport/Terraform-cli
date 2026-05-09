#!/bin/bash

# Устанавливает fail2ban и jail для sshd. Порт в jail: applications.ssh.port
# при наличии, иначе текущий VPS_PORT (как в credentials после смены порта).

# Определить публичный IPv4 локальной машины-установщика.
# Возврат: IP на stdout или пустая строка, если определить не удалось.
_installer_public_ipv4() {
    local ip=""
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -4 -fsS https://api.ipify.org 2>/dev/null || true)
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { printf '%s' "$ip"; return 0; }
    fi
    if command -v wget >/dev/null 2>&1; then
        ip=$(wget -4 -qO- https://api.ipify.org 2>/dev/null || true)
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { printf '%s' "$ip"; return 0; }
    fi
    printf '%s' ""
}

setup_fail2ban() {
    local ssh_port_for_jail
    local installer_ip

    skip_unless_application fail2ban

    if ! config_application_enabled ssh; then
        message "Fail2ban пропущен" "нет секции applications.ssh" "$YELLOW" "$YELLOW"
        return 0 2>/dev/null || exit 0
    fi

    ssh_port_for_jail=$(vps_ssh_application_port_optional)
    [[ -z "$ssh_port_for_jail" ]] && ssh_port_for_jail="$VPS_PORT"
    installer_ip=$(_installer_public_ipv4)

    title "Настройка блокировщика (fail2ban)" "$BLUE"
    if [[ -n "$installer_ip" ]]; then
        message "Fail2ban ignoreip (установщик)" "$installer_ip" "$YELLOW" "$CYAN"
    else
        message "Fail2ban ignoreip (установщик)" "не удалось определить публичный IP" "$YELLOW" "$YELLOW"
    fi

    if run_ssh_bash \
        "export SSH_PORT_FOR_JAIL=$ssh_port_for_jail FAIL2BAN_IGNORE_IP=$installer_ip" \
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
