#!/bin/bash

# Модуль AmneziaWG на ПК: запускает remote.sh на VPS через run_ssh_bash.
# Порт берётся из config.yml (vps.applications.amneziawg.port). Нужен включённый блок applications.amneziawg.

# Прочитать порт AmneziaWG из config.yml.
# Параметры: нет (читает CONFIGURATIONS). Возврат: номер порта на stdout.
_read_awg_port() {
    yq e '.vps.applications.amneziawg.port' "$CONFIGURATIONS"
}

# Прочитать имя образа из config.yml (с умолчанием на официальный AWG2 образ).
# Параметры: нет (читает CONFIGURATIONS). Возврат: имя образа на stdout.
_read_awg_image() {
    local img
    img=$(yq e '(.vps.applications.amneziawg.image // "amneziavpn/amneziawg-go:latest")' "$CONFIGURATIONS")
    [[ -z "$img" || "$img" == "null" ]] && img="amneziavpn/amneziawg-go:latest"
    printf '%s' "$img"
}

# Проверить, запущен ли контейнер AmneziaWG на сервере.
# Параметры: нет. Возврат: 0 если контейнер найден, иначе код ошибки.
awg_container_running() {
    run_ssh_bash \
        "export AWG_ACTION=check AWG_CONTAINER=amnezia-awg2 AWG_PORT=1 AWG_PUBLIC_HOST=127.0.0.1" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
}

# Установить AmneziaWG на VPS и после успеха показать клиентский конфиг + QR-код.
# Параметры: нет (читает CONFIGURATIONS, VPS_IP). Возврат: код ошибки при неудаче.
install_amneziawg() {
    local port image
    port=$(_read_awg_port)
    image=$(_read_awg_image)

    step_name "Установка AmneziaWG (Docker)" "$YELLOW"
    if run_ssh_bash \
        "export AWG_ACTION=install AWG_CONTAINER=amnezia-awg2 AWG_IMAGE=${image} AWG_PORT=${port} AWG_PUBLIC_HOST=${VPS_IP}" \
        "$(dirname "$BASH_SOURCE")/remote.sh"; then
        step_status "Выполнено" "$GREEN"
        _awg_copy_manage_script
        print_awg_client_config
        print_awg_qr_code
        _print_awg_add_client_hint
    else
        local result=$?
        step_status "Ошибка ($result)" "$RED"
        print_last_remote_script_log_path
        return "$result"
    fi
    return 0
}

# Получить с сервера клиентский конфиг и положить в лог SSH.
# Параметры: нет. Возврат: код удалённого сценария.
load_awg_client_config() {
    local port
    port=$(_read_awg_port)
    run_ssh_bash \
        "export AWG_ACTION=client AWG_CONTAINER=amnezia-awg2 AWG_PORT=${port} AWG_PUBLIC_HOST=${VPS_IP}" \
        "$(dirname "$BASH_SOURCE")/remote.sh"
    return $?
}

# Добавить нового клиента AmneziaWG на VPS.
# Параметры: нет. Возврат: 0 при успехе; при ошибке — код и путь к логу.
add_awg_client() {
    local port image
    port=$(_read_awg_port)
    image=$(_read_awg_image)

    step_name "Добавление нового клиента AmneziaWG" "$YELLOW"
    if run_ssh_bash \
        "export AWG_ACTION=add_client AWG_CONTAINER=amnezia-awg2 AWG_IMAGE=${image} AWG_PORT=${port} AWG_PUBLIC_HOST=${VPS_IP}" \
        "$(dirname "$BASH_SOURCE")/remote.sh"; then
        step_status "ОК" "$GREEN"
        print_awg_client_config
        print_awg_qr_code
    else
        local result=$?
        step_status "Ошибка ($result)" "$RED"
        print_last_remote_script_log_path
        return "$result"
    fi
    return 0
}

# Извлечь из лога SSH клиентский конфиг AmneziaWG (между маркерами) и вывести в консоль.
# Параметры: нет (читает LAST_REMOTE_SCRIPT_LOG). Возврат: 0.
_extract_last_awg_block_from_log() {
    local log_path="$1"
    local begin_marker="$2"
    local end_marker="$3"
    awk -v b="$begin_marker" -v e="$end_marker" '
        $0 == b {in_block=1; cur=""; next}
        $0 == e {if (in_block) {last=cur}; in_block=0; next}
        in_block {cur = cur $0 ORS}
        END {printf "%s", last}
    ' "$log_path" 2>/dev/null || true
}

print_awg_client_config() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local config=""

    [[ -n "$log_path" && -f "$log_path" ]] || {
        message "AmneziaWG client config" "нет файла лога" "$YELLOW" "$YELLOW"
        return 0
    }

    config=$(_extract_last_awg_block_from_log \
        "$log_path" \
        "--- AWG-CLIENT-CONFIG-BEGIN ---" \
        "--- AWG-CLIENT-CONFIG-END ---")

    if [[ -z "$config" ]]; then
        message "AmneziaWG client config" "не найден в логе; см. $log_path" "$YELLOW" "$YELLOW"
        return 0
    fi

    printf '\n%s\n\n' "$config"
}

# Скопировать remote.sh на VPS как /opt/amneziawg/manage.sh и создать /opt/amneziawg/add_client.sh.
# Параметры: нет. Возврат: 0 при успехе, не 0 при ошибке SSH.
_awg_copy_manage_script() {
    local awg_port img timeout ssh_port
    awg_port=$(_read_awg_port)
    img=$(_read_awg_image)
    timeout=$(ssh_connect_timeout)
    while IFS= read -r ssh_port; do
        [[ -n "$ssh_port" ]] || continue
        ssh -q -o ConnectTimeout="$timeout" -p "$ssh_port" "$VPS_USER@$VPS_IP" \
            "sudo mkdir -p /opt/amneziawg && sudo tee /opt/amneziawg/manage.sh > /dev/null && sudo chmod 700 /opt/amneziawg/manage.sh" \
            < "$(dirname "${BASH_SOURCE[0]}")/remote.sh" 2>/dev/null || continue

        # Создать обёртку add_client.sh с зашитыми параметрами этого VPS.
        printf '#!/bin/bash\nAWG_ACTION=add_client AWG_PORT=%s AWG_PUBLIC_HOST=%s AWG_CONTAINER=amnezia-awg2 AWG_IMAGE=%s bash /opt/amneziawg/manage.sh\n' \
            "$awg_port" "$VPS_IP" "$img" \
            | ssh -q -o ConnectTimeout="$timeout" -p "$ssh_port" "$VPS_USER@$VPS_IP" \
                "sudo tee /opt/amneziawg/add_client.sh > /dev/null && sudo chmod +x /opt/amneziawg/add_client.sh" 2>/dev/null || true

        return 0
    done < <(ssh_port_candidates)
    return 1
}

# Вывести подсказку с готовой SSH-командой добавления нового клиента.
# Параметры: нет. Возврат: 0.
_print_awg_add_client_hint() {
    local port img
    port=$(_read_awg_port)
    img=$(_read_awg_image)
    local ssh_cmd
    ssh_cmd="ssh -p ${VPS_PORT} ${VPS_USER}@${VPS_IP} 'sudo /opt/amneziawg/add_client.sh'"
    echo
    printf '%b%s%b\n' "$CYAN" "Добавить нового клиента AmneziaWG:" "$NC"
    printf '%b%s%b\n\n' "$BLACK" "$ssh_cmd" "$NC"
}

# Извлечь из лога SSH QR-код и вывести в консоль (если qrencode был установлен на сервере).
# Параметры: нет (читает LAST_REMOTE_SCRIPT_LOG). Возврат: 0.
print_awg_qr_code() {
    local log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
    local qr=""

    [[ -n "$log_path" && -f "$log_path" ]] || return 0

    qr=$(_extract_last_awg_block_from_log \
        "$log_path" \
        "--- AWG-CLIENT-QR-BEGIN ---" \
        "--- AWG-CLIENT-QR-END ---")

    [[ -n "$qr" ]] || return 0
    printf '\n%s\n\n' "$qr"
}

# Главная ветка модуля: установить AmneziaWG или показать конфиг, если уже работает.
# Параметры: нет (читает CONFIGURATIONS). Возврат: exit 1 при ошибке.
setup_amneziawg() {
    title "Установка AmneziaWG VPN (Docker)" "$BLUE"

    step_name "Проверка: контейнер AmneziaWG запущен" "$YELLOW"
    if awg_container_running; then
        step_status "Да" "$GREEN"
        step_name "Получение клиентского конфига AmneziaWG" "$YELLOW"
        if load_awg_client_config; then
            step_status "ОК" "$GREEN"
            _awg_copy_manage_script
            print_awg_client_config
            print_awg_qr_code
            _print_awg_add_client_hint
        else
            step_status "Ошибка" "$RED"
            print_last_remote_script_log_path
        fi
    else
        step_status "Нет" "$YELLOW"
        install_amneziawg
    fi
}

if config_application_enabled amneziawg; then
    setup_amneziawg
fi
