#!/bin/bash

# Модуль WireGuard: запускает WireGuard VPN в Docker (linuxserver/wireguard).
# При первом запуске устанавливает сервер и показывает конфиг первого клиента.
# При повторном — проверяет контейнер и показывает сохранённый конфиг.
# Нужен включённый блок applications.wireguard в config.yml (и applications.docker).

# Читает Docker-образ из config.yml (по умолчанию linuxserver/wireguard:latest).
_read_wg_image() {
    local img
    img=$(yq e '(.vps.applications.wireguard.image // "linuxserver/wireguard:latest")' "$CONFIGURATIONS")
    [[ -z "$img" || "$img" == "null" ]] && img="linuxserver/wireguard:latest"
    printf '%s' "$img"
}

# Читает порт WireGuard из config.yml (по умолчанию 51820).
_read_wg_port() {
    local p
    p=$(yq e '(.vps.applications.wireguard.port // 51820)' "$CONFIGURATIONS")
    [[ -z "$p" || "$p" == "null" ]] && p=51820
    printf '%s' "$p"
}

# Читает базовую сеть туннеля из config.yml (по умолчанию 10.8.0.0).
_read_wg_network() {
    local net
    net=$(yq e '(.vps.applications.wireguard.network // "10.8.0.0")' "$CONFIGURATIONS")
    [[ -z "$net" || "$net" == "null" ]] && net="10.8.0.0"
    printf '%s' "$net"
}

# Читает DNS для клиентов из config.yml (по умолчанию 1.1.1.1).
_read_wg_dns() {
    local dns
    dns=$(yq e '(.vps.applications.wireguard.dns // "1.1.1.1")' "$CONFIGURATIONS")
    [[ -z "$dns" || "$dns" == "null" ]] && dns="1.1.1.1"
    printf '%s' "$dns"
}

# Читает разрешённые IP-диапазоны для клиентов из config.yml (по умолчанию 0.0.0.0/0).
_read_wg_allowed_ips() {
    local ips
    ips=$(yq e '(.vps.applications.wireguard.allowed-ips // "0.0.0.0/0")' "$CONFIGURATIONS")
    [[ -z "$ips" || "$ips" == "null" ]] && ips="0.0.0.0/0"
    printf '%s' "$ips"
}

# Извлечь блок текста из лога SSH между двумя маркерами (берётся последнее вхождение).
_extract_wg_block_from_log() {
    local log_path="$1"
    local begin_marker="$2"
    local end_marker="$3"
    awk -v b="$begin_marker" -v e="$end_marker" '
        $0 == b { in_block=1; cur=""; next }
        $0 == e { if (in_block) { last=cur }; in_block=0; next }
        in_block { cur = cur $0 ORS }
        END { printf "%s", last }
    ' "$log_path" 2>/dev/null || true
}

# Вывести конфиг клиента WireGuard из лога последнего удалённого сценария.
print_wg_client_config() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local config=""

    [[ -n "$log_path" && -f "$log_path" ]] || {
        message "WireGuard client config" "нет файла лога" "$YELLOW" "$YELLOW"
        return 0
    }

    config=$(_extract_wg_block_from_log \
        "$log_path" \
        "--- WG-CLIENT-CONFIG-BEGIN ---" \
        "--- WG-CLIENT-CONFIG-END ---")

    if [[ -z "$config" ]]; then
        message "WireGuard client config" "не найден в логе; см. $log_path" "$YELLOW" "$YELLOW"
        return 0
    fi

    printf '\n%s\n\n' "$config"
}

# Вывести QR-код клиента WireGuard из лога (если qrencode был установлен на VPS).
print_wg_qr_code() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local qr=""

    [[ -n "$log_path" && -f "$log_path" ]] || return 0

    qr=$(_extract_wg_block_from_log \
        "$log_path" \
        "--- WG-CLIENT-QR-BEGIN ---" \
        "--- WG-CLIENT-QR-END ---")

    [[ -n "$qr" ]] || return 0
    printf '\n%s\n\n' "$qr"
}

# Скопировать remote.sh на VPS как /opt/wireguard/manage.sh и создать /opt/wireguard/add_client.sh и /opt/wireguard/get_client.sh.
_wg_copy_manage_script() {
    local wg_port wg_image wg_network wg_dns wg_allowed_ips timeout ssh_port
    wg_port=$(_read_wg_port)
    wg_image=$(_read_wg_image)
    wg_network=$(_read_wg_network)
    wg_dns=$(_read_wg_dns)
    wg_allowed_ips=$(_read_wg_allowed_ips)
    timeout=$(ssh_connect_timeout)

    while IFS= read -r ssh_port; do
        [[ -n "$ssh_port" ]] || continue
        ssh -q -o ConnectTimeout="$timeout" -p "$ssh_port" "$VPS_USER@$VPS_IP" \
            "sudo mkdir -p /opt/wireguard && sudo tee /opt/wireguard/manage.sh > /dev/null && sudo chmod 700 /opt/wireguard/manage.sh" \
            < "$(dirname "${BASH_SOURCE[0]}")/remote.sh" 2>/dev/null || continue

        printf '#!/bin/bash\nWG_ACTION=add_client WG_PORT=%q WG_PUBLIC_HOST=%q WG_CONTAINER=wireguard WG_IMAGE=%q WG_NETWORK=%q WG_DNS=%q WG_ALLOWED_IPS=%q bash /opt/wireguard/manage.sh\n' \
            "$wg_port" "$VPS_IP" "$wg_image" "$wg_network" "$wg_dns" "$wg_allowed_ips" \
            | ssh -q -o ConnectTimeout="$timeout" -p "$ssh_port" "$VPS_USER@$VPS_IP" \
                "sudo tee /opt/wireguard/add_client.sh > /dev/null && sudo chmod +x /opt/wireguard/add_client.sh" 2>/dev/null || true

        printf '#!/bin/bash\nnum=\"${1:-1}\"\nWG_ACTION=get_client WG_CLIENT_NUM=\"${num}\" WG_PORT=%q WG_PUBLIC_HOST=%q WG_CONTAINER=wireguard WG_IMAGE=%q WG_NETWORK=%q WG_DNS=%q WG_ALLOWED_IPS=%q bash /opt/wireguard/manage.sh\n' \
            "$wg_port" "$VPS_IP" "$wg_image" "$wg_network" "$wg_dns" "$wg_allowed_ips" \
            | ssh -q -o ConnectTimeout="$timeout" -p "$ssh_port" "$VPS_USER@$VPS_IP" \
                "sudo tee /opt/wireguard/get_client.sh > /dev/null && sudo chmod +x /opt/wireguard/get_client.sh" 2>/dev/null || true

        return 0
    done < <(ssh_port_candidates)
    return 1
}

# Вывести подсказку с командой добавления нового клиента WireGuard.
_print_wg_add_client_hint() {
    local ssh_cmd
    local ssh_get_cmd
    ssh_cmd="ssh -p ${VPS_PORT} ${VPS_USER}@${VPS_IP} 'sudo /opt/wireguard/add_client.sh'"
    ssh_get_cmd="ssh -p ${VPS_PORT} ${VPS_USER}@${VPS_IP} 'sudo /opt/wireguard/get_client.sh <номер_клиента>'"
    echo
    printf '%b%s%b\n' "$CYAN" "Добавить нового клиента WireGuard:" "$NC"
    printf '%b%s%b\n' "$BLACK" "$ssh_cmd" "$NC"
    printf '%b%s%b\n' "$CYAN" "Получить конфиг клиента WireGuard по номеру:" "$NC"
    printf '%b%s%b\n\n' "$BLACK" "$ssh_get_cmd" "$NC"
}

# Собрать строку экспорта переменных окружения для remote.sh.
_wg_env() {
    local action="$1"
    local port image network dns allowed_ips
    port=$(_read_wg_port)
    image=$(_read_wg_image)
    network=$(_read_wg_network)
    dns=$(_read_wg_dns)
    allowed_ips=$(_read_wg_allowed_ips)
    printf 'export WG_ACTION=%q WG_PORT=%q WG_PUBLIC_HOST=%q WG_IMAGE=%q WG_NETWORK=%q WG_DNS=%q WG_ALLOWED_IPS=%q' \
        "$action" "$port" "$VPS_IP" "$image" "$network" "$dns" "$allowed_ips"
}

# Проверить, запущен ли контейнер WireGuard на сервере.
wg_container_running() {
    run_ssh_bash \
        "export WG_ACTION=check WG_PORT=1 WG_PUBLIC_HOST=127.0.0.1 WG_CONTAINER=wireguard" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
}

# Показать конфиг первого клиента с уже запущенного сервера.
load_wg_client_config() {
    run_ssh_bash \
        "$(_wg_env client)" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
    return $?
}

# Установить WireGuard на VPS.
install_wireguard() {
    local port image network dns allowed_ips
    port=$(_read_wg_port)
    image=$(_read_wg_image)
    network=$(_read_wg_network)
    dns=$(_read_wg_dns)
    allowed_ips=$(_read_wg_allowed_ips)

    message "Docker-образ" "$image" "$YELLOW" "$CYAN"
    message "Порт" "${port}/udp" "$YELLOW" "$CYAN"
    message "Сеть туннеля" "${network}/24" "$YELLOW" "$CYAN"
    message "DNS клиентов" "$dns" "$YELLOW" "$CYAN"
    message "AllowedIPs" "$allowed_ips" "$YELLOW" "$CYAN"

    step_name "Установка WireGuard (Docker)" "$YELLOW"
    if run_ssh_bash \
        "$(_wg_env install)" \
        "$(dirname "$BASH_SOURCE")/remote.sh"; then
        step_status "Выполнено" "$GREEN"
        _wg_copy_manage_script
        print_wg_client_config
        print_wg_qr_code
        _print_wg_add_client_hint
    else
        local result=$?
        step_status "Ошибка ($result)" "$RED"
        print_last_remote_script_log_path
        return "$result"
    fi
    return 0
}

# Главная ветка: проверить наличие контейнера — установить или показать конфиг.
setup_wireguard() {
    title "Установка WireGuard VPN (Docker)" "$BLUE"

    step_name "Проверка: контейнер WireGuard запущен" "$YELLOW"
    if wg_container_running; then
        step_status "Да" "$GREEN"
        message "Docker-образ" "$(_read_wg_image)" "$YELLOW" "$CYAN"
        step_name "Получение конфига клиента WireGuard" "$YELLOW"
        if load_wg_client_config; then
            step_status "ОК" "$GREEN"
            _wg_copy_manage_script
            print_wg_client_config
            print_wg_qr_code
            _print_wg_add_client_hint
        else
            step_status "Конфиг не найден, восстановление" "$YELLOW"
            print_last_remote_script_log_path
            install_wireguard || exit 1
        fi
    else
        step_status "Нет" "$YELLOW"
        install_wireguard || exit 1
    fi
}

if config_application_enabled wireguard; then
    setup_wireguard
fi
