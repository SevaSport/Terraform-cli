#!/bin/bash

# Добавить нового клиента AmneziaWG на уже настроенный VPS.
# Использование:  ./add_client.sh
# Читает credentials.yml и config.yml так же, как run.sh.

BASE_DIR=$(cd "$(dirname "$BASH_SOURCE")/../../.." && pwd)
LOGS_DIR="$BASE_DIR/logs"
DIST_DIR="$BASE_DIR/dist"
LIBS_SCRIPTS="$DIST_DIR/libs"
CONFIGURATIONS="$BASE_DIR/config.yml"
CREDENTIALS="$BASE_DIR/credentials.yml"

mkdir -p "$LOGS_DIR"

source "$LIBS_SCRIPTS/shell-messages.sh"
source "$LIBS_SCRIPTS/vps-config.sh"
source "$LIBS_SCRIPTS/ssh.sh"

# Загрузить реквизиты подключения из credentials.yml.
VPS_IP=$(yq e '.vps.ip // ""' "$CREDENTIALS" 2>/dev/null || true)
VPS_PORT=$(yq e '.vps.port // ""' "$CREDENTIALS" 2>/dev/null || true)
VPS_USER=$(yq e '.vps.user // ""' "$CREDENTIALS" 2>/dev/null || true)
VPS_PASS=$(yq e '.vps.pass // ""' "$CREDENTIALS" 2>/dev/null || true)
[[ "$VPS_IP"   == "null" ]] && VPS_IP=""
[[ "$VPS_PORT" == "null" ]] && VPS_PORT=""
[[ "$VPS_USER" == "null" ]] && VPS_USER=""
[[ "$VPS_PASS" == "null" ]] && VPS_PASS=""

# Если в credentials.yml записан новый порт SSH (после изменения) — используем его.
_ssh_cfg_port=$(vps_ssh_application_port_optional 2>/dev/null || true)
[[ -n "$_ssh_cfg_port" && "$_ssh_cfg_port" != "null" ]] && VPS_PORT="$_ssh_cfg_port"

if [[ -z "$VPS_IP" ]]; then
    message "IP VPS" "не задан в credentials.yml" "$RED" "$RED"
    exit 1
fi

title "Добавление клиента AmneziaWG на $VPS_IP" "$BLUE"
message "IP адрес" "$VPS_IP" "$YELLOW" "$GREEN"
message "SSH порт" "$VPS_PORT" "$YELLOW" "$GREEN"
message "Пользователь" "$VPS_USER" "$YELLOW" "$GREEN"

# Подключаем модуль AmneziaWG, используя уже загруженные переменные.
source "$DIST_DIR/install/amneziawg/task.sh" --source-only 2>/dev/null || true

# Переопределяем функции чтобы избежать setup_amneziawg при source.
# Вместо этого запускаем только add_awg_client напрямую через SSH.
_add_client_direct() {
    local port image
    port=$(_read_awg_port)
    image=$(_read_awg_image)

    step_name "Добавление нового клиента AmneziaWG" "$YELLOW"
    if run_ssh_bash \
        "export AWG_ACTION=add_client AWG_CONTAINER=amnezia-awg2 AWG_IMAGE=${image} AWG_PORT=${port} AWG_PUBLIC_HOST=${VPS_IP}" \
        "$DIST_DIR/install/amneziawg/remote.sh"; then
        step_status "ОК" "$GREEN"
    else
        local result=$?
        step_status "Ошибка ($result)" "$RED"
        print_last_remote_script_log_path
        exit "$result"
    fi
}

_add_client_direct

# Достать и вывести конфиг из лога.
log_path="${LAST_REMOTE_SCRIPT_LOG:-}"
if [[ -n "$log_path" && -f "$log_path" ]]; then
    client_num=$(grep -o 'AWG_NEW_CLIENT_NUM=[0-9]*' "$log_path" | tail -1 | cut -d= -f2)
    [[ -n "$client_num" ]] && title "Клиент №${client_num}" "$BLUE"

    config=$(awk '/^--- AWG-CLIENT-CONFIG-BEGIN ---/{found=1; next} /^--- AWG-CLIENT-CONFIG-END ---/{found=0} found{print}' "$log_path" 2>/dev/null || true)
    if [[ -n "$config" ]]; then
        echo
        printf '%s\n' "$config"
        echo
        message "Конфиг сохранён в" "$log_path" "$YELLOW" "$CYAN"
    fi

    qr=$(awk '/^--- AWG-CLIENT-QR-BEGIN ---/{found=1; next} /^--- AWG-CLIENT-QR-END ---/{found=0} found{print}' "$log_path" 2>/dev/null || true)
    if [[ -n "$qr" ]]; then
        title "QR-код для сканирования в приложении Amnezia" "$BLUE"
        printf '%s\n\n' "$qr"
    fi
fi
