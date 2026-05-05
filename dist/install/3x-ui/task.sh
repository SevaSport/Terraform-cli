#!/bin/bash

# Отдельный шаг установки панели 3x-ui (без Docker) после Outline.
# Использует настройки из vps.applications.3xui в config.yml.

# Прочитать настройки 3x-ui из config.yml в переменные panel_port, panel_user, panel_pass.
# Параметры: нет. Побочный эффект — устанавливает локальные переменные вызывающего контекста.
_read_3xui_config() {
    panel_port=$(yq e '.vps.applications.3xui."panel-port" // "61197"' "$CONFIGURATIONS")
    [[ -z "$panel_port" || "$panel_port" == "null" ]] && panel_port="61197"
    panel_user=$(yq e '.vps.applications.3xui."panel-user" // ""' "$CONFIGURATIONS")
    panel_pass=$(yq e '.vps.applications.3xui."panel-pass" // ""' "$CONFIGURATIONS")
}

print_3xui_access_payload() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local panel_url=""
    local panel_login=""
    local panel_password=""

    [[ -n "$log_path" && -f "$log_path" ]] || {
        message "3x-ui доступ" "нет файла лога" "$YELLOW" "$YELLOW"
        return 0
    }

    panel_url=$(grep -aEo 'XUI_PANEL_URL=.*' "$log_path" 2>/dev/null | tail -n1 || true)
    panel_url="${panel_url#XUI_PANEL_URL=}"
    panel_login=$(grep -aEo 'XUI_PANEL_LOGIN=.*' "$log_path" 2>/dev/null | tail -n1 || true)
    panel_login="${panel_login#XUI_PANEL_LOGIN=}"
    panel_password=$(grep -aEo 'XUI_PANEL_PASSWORD=.*' "$log_path" 2>/dev/null | tail -n1 || true)
    panel_password="${panel_password#XUI_PANEL_PASSWORD=}"

    if [[ -z "$panel_url" ]]; then
        message "3x-ui доступ" "не найден в логе; см. $log_path" "$YELLOW" "$YELLOW"
        return 0
    fi

    echo
    printf '%s\n' "$panel_url"
    echo
    [[ -n "$panel_login" ]] && message "Логин" "$panel_login" "$YELLOW" "$CYAN"
    [[ -n "$panel_password" ]] && message "Пароль" "$panel_password" "$YELLOW" "$CYAN"
}

is_3xui_running() {
    run_ssh "sudo -n systemctl is-active --quiet x-ui" >/dev/null 2>&1
}

check_3xui_requirements() {
    if ! run_ssh "sudo -n sh -lc 'test -x /usr/local/x-ui/x-ui && systemctl list-unit-files | grep -q \"^x-ui\\.service\"'"; then
        message "3x-ui на сервере" "не установлен" "$YELLOW" "$YELLOW"
        return 1
    fi

    return 0
}

open_3xui_acme_port() {
    if ! config_application_enabled ufw; then
        return 0
    fi
    message "UFW: разрешен ACME challenge (3x-ui SSL)" "80/tcp" "$YELLOW" "$CYAN"
    run_ssh "sudo -n ufw allow 80/tcp comment '3x-ui ACME' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}

close_3xui_acme_port() {
    if ! config_application_enabled ufw; then
        return 0
    fi
    run_ssh "sudo -n ufw delete allow 80/tcp >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    message "UFW: закрыт ACME challenge (3x-ui SSL)" "80/tcp" "$YELLOW" "$CYAN"
}

has_3xui_cert() {
    run_ssh "sudo -n /usr/local/x-ui/x-ui setting -getCert 2>/dev/null | awk -F': ' '/^cert:/ {print \$2}' | tr -d '[:space:]' | grep -q ." >/dev/null 2>&1
}

enforce_3xui_panel_port() {
    local panel_port="$1"
    [[ -n "$panel_port" && "$panel_port" != "null" ]] || return 0
    run_ssh "sudo -n /usr/local/x-ui/x-ui setting -port ${panel_port} >/dev/null 2>&1 && sudo -n systemctl restart x-ui >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}

load_3xui_access_payload() {
    local panel_port panel_user panel_pass panel_user_q panel_pass_q
    _read_3xui_config

    if [[ (-n "$panel_user" && -z "$panel_pass") || (-z "$panel_user" && -n "$panel_pass") ]]; then
        message "3x-ui логин/пароль" "укажите и panel-user, и panel-pass" "$YELLOW" "$RED"
        exit 1
    fi

    panel_user_q=$(printf '%q' "$panel_user")
    panel_pass_q=$(printf '%q' "$panel_pass")
    run_ssh_bash \
        "export XUI_ACTION=payload XUI_PANEL_PORT=${panel_port} XUI_PANEL_USER=${panel_user_q} XUI_PANEL_PASS=${panel_pass_q} XUI_SERVER_HOST=${VPS_IP}" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
}

setup_3xui() {
    local panel_port panel_user panel_pass panel_user_q panel_pass_q

    title "Установка панели 3x-ui" "$BLUE"

    _read_3xui_config
    panel_user_q=$(printf '%q' "$panel_user")
    panel_pass_q=$(printf '%q' "$panel_pass")

    if check_3xui_requirements; then
        message "Панель 3x-ui на сервере" "уже работает" "$YELLOW" "$GREEN"
        load_3xui_access_payload || true
        enforce_3xui_panel_port "$panel_port"
        load_3xui_access_payload || true
        print_3xui_access_payload
    else
        message "Запуск установщика 3x-ui на сервере" "выполняется" "$YELLOW" "$GREEN"
        open_3xui_acme_port
        step_name "Установка 3x-ui" "$YELLOW"
        if run_ssh_bash \
            "export XUI_ACTION=install XUI_PANEL_PORT=${panel_port} XUI_PANEL_USER=${panel_user_q} XUI_PANEL_PASS=${panel_pass_q} XUI_SERVER_HOST=${VPS_IP}" \
            "$(dirname "$BASH_SOURCE")/remote.sh"; then
            step_status "Выполнено" "$GREEN"
            enforce_3xui_panel_port "$panel_port"
            if has_3xui_cert; then
                close_3xui_acme_port
            else
                message "UFW: ACME challenge (3x-ui SSL)" "сертификат не найден, порт 80 оставлен открытым" "$YELLOW" "$YELLOW"
            fi
            load_3xui_access_payload || true
            print_3xui_access_payload
        else
            step_status "Ошибка" "$RED"
            print_last_remote_script_log_path
            exit 1
        fi
    fi
}

if config_application_enabled "3xui"; then
    setup_3xui
fi
