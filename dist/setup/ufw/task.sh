#!/bin/bash

# Если в config.yml включён applications.ufw: на сервере ставится ufw,
# задаются политики и разрешения для SSH (актуальный порт), OpenVPN и
# Outline по данным из того же config.

setup_ufw() {
    local ssh_cfg
    local ssh_rule_port_1
    local ssh_rule_port_2
    local openvpn_port
    local outline_api_port
    local outline_keys_port
    local mtproto_port

    skip_unless_application ufw
    title "Настройка межсетевого экрана (UFW)" "$BLUE"

    ssh_cfg=$(vps_ssh_application_port_optional)
    ssh_rule_port_1="$VPS_PORT"
    ssh_rule_port_2=""
    if [[ -n "$ssh_cfg" && "$ssh_cfg" != "$VPS_PORT" ]]; then
        ssh_rule_port_2="$ssh_cfg"
    fi

    openvpn_port=""
    if config_application_enabled openvpn; then
        openvpn_port=$(yq e '.vps.applications.openvpn.port' "$CONFIGURATIONS")
    fi

    outline_api_port=""
    outline_keys_port=""
    if config_application_enabled outline; then
        outline_api_port=$(yq e '.vps.applications.outline.port.api' "$CONFIGURATIONS")
        outline_keys_port=$(yq e '.vps.applications.outline.port.keys' "$CONFIGURATIONS")
    fi

    mtproto_port=""
    if config_application_enabled mtproto; then
        mtproto_port=$(yq e '.vps.applications.mtproto.port // 443' "$CONFIGURATIONS")
    fi

    message "UFW: разрешен SSH (основной)" "${ssh_rule_port_1}/tcp" "$YELLOW" "$CYAN"
    if [[ -n "${ssh_rule_port_2:-}" ]]; then
        message "UFW: разрешен SSH (дополнительный)" "${ssh_rule_port_2}/tcp" "$YELLOW" "$CYAN"
    fi
    if [[ -n "${openvpn_port:-}" && "${openvpn_port}" != "null" ]]; then
        message "UFW: разрешен OpenVPN" "${openvpn_port}/udp" "$YELLOW" "$CYAN"
    fi
    if [[ -n "${outline_api_port:-}" && "${outline_api_port}" != "null" ]]; then
        message "UFW: разрешен Outline API" "${outline_api_port}/tcp" "$YELLOW" "$CYAN"
    fi
    if [[ -n "${outline_keys_port:-}" && "${outline_keys_port}" != "null" ]]; then
        message "UFW: разрешен Outline keys" "${outline_keys_port}/tcp" "$YELLOW" "$CYAN"
    fi
    if [[ -n "${mtproto_port:-}" && "${mtproto_port}" != "null" ]]; then
        message "UFW: разрешен MTProto proxy" "${mtproto_port}/tcp" "$YELLOW" "$CYAN"
    fi
    if run_ssh_bash \
        "export SSH_RULE_PORT_1=$ssh_rule_port_1 SSH_RULE_PORT_2=${ssh_rule_port_2:-} OPENVPN_PORT=${openvpn_port:-} OUTLINE_API_PORT=${outline_api_port:-} OUTLINE_KEYS_PORT=${outline_keys_port:-} MTPROTO_PORT=${mtproto_port:-}" \
        "$SETUP_SCRIPTS/ufw/remote.sh"; then
        message "Настройка UFW" "Выполнена" "$YELLOW" "$GREEN"
        message "Сервис UFW" "Запущен" "$YELLOW" "$GREEN"
    else
        message "Настройка UFW" "Ошибка" "$YELLOW" "$RED"
        print_last_remote_script_log_path
        message "Продолжение выполнения" "без UFW" "$RED" "$RED"
    fi
}

setup_ufw
