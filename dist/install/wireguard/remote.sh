#!/bin/bash
# Выполняется на VPS: WireGuard VPN в Docker (linuxserver/wireguard — официальный образ).
#
# WG_ACTION:
#   install    — pull образа, первый запуск, конфиг peer1; пропускается если контейнер уже есть.
#   check      — проверить, запущен ли контейнер WG_CONTAINER.
#   client     — напечатать конфиг первого клиента + QR-код.
#   get_client — напечатать конфиг клиента по номеру WG_CLIENT_NUM + QR-код.
#   add_client — перезапустить контейнер с PEERS+1, вывести конфиг нового клиента + QR-код.
#
# Обязательные: WG_PORT, WG_PUBLIC_HOST
# Опциональные: WG_IMAGE, WG_CONTAINER, WG_NETWORK, WG_DNS, WG_ALLOWED_IPS, WG_DATA_DIR
set -euo pipefail
type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

WG_ACTION="${WG_ACTION:-install}"
WG_CONTAINER="${WG_CONTAINER:-wireguard}"
WG_IMAGE="${WG_IMAGE:-linuxserver/wireguard:latest}"
WG_PORT="${WG_PORT:?WG_PORT is required}"
WG_PUBLIC_HOST="${WG_PUBLIC_HOST:?WG_PUBLIC_HOST is required}"
WG_DATA_DIR="${WG_DATA_DIR:-/opt/wireguard}"
WG_NETWORK="${WG_NETWORK:-10.8.0.0}"
WG_DNS="${WG_DNS:-1.1.1.1}"
WG_ALLOWED_IPS="${WG_ALLOWED_IPS:-0.0.0.0/0}"
WG_CLIENT_NUM="${WG_CLIENT_NUM:-1}"

# Файл для хранения текущего числа сгенерированных клиентов между запусками.
WG_PEERS_FILE="${WG_DATA_DIR}/.peers_count"

# --- Утилиты -----------------------------------------------------------------------

# Проверить, запущен ли контейнер WireGuard.
wg_check_running() {
    _sudo docker ps --format '{{.Names}}' | grep -qx "${WG_CONTAINER}"
}

# Прочитать сохранённое число клиентов (по умолчанию 1).
_wg_peers_count() {
    if _sudo test -f "$WG_PEERS_FILE"; then
        _sudo cat "$WG_PEERS_FILE"
    else
        echo "1"
    fi
}

# Запустить/перезапустить контейнер с заданным числом пиров PEERS=N.
# linuxserver/wireguard при PEERS=N создаёт peer1 … peerN,
# уже существующие конфиги не перезаписываются — только новые добавляются.
_wg_run_container() {
    local peers="$1"
    echo "Docker-образ: ${WG_IMAGE}" >&2
    if _sudo docker ps -a --format '{{.Names}}' | grep -qx "${WG_CONTAINER}"; then
        _sudo docker rm -f "${WG_CONTAINER}" >/dev/null
    fi
    _sudo docker run -d \
        --name  "${WG_CONTAINER}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --sysctl net.ipv4.conf.all.src_valid_mark=1 \
        -p "${WG_PORT}:51820/udp" \
        -v "${WG_DATA_DIR}/config:/config" \
        -v /lib/modules:/lib/modules \
        -e PUID=0 \
        -e PGID=0 \
        -e TZ=UTC \
        -e SERVERURL="${WG_PUBLIC_HOST}" \
        -e SERVERPORT="${WG_PORT}" \
        -e PEERS="${peers}" \
        -e PEERDNS="${WG_DNS}" \
        -e INTERNAL_SUBNET="${WG_NETWORK}" \
        -e ALLOWEDIPS="${WG_ALLOWED_IPS}" \
        -e LOG_CONFS=true \
        "${WG_IMAGE}" >/dev/null
}

# Ждать появления конфигурационного файла клиента (до 120 секунд).
_wg_wait_for_peer() {
    local peer_num="$1"
    local conf_path="${WG_DATA_DIR}/config/peer${peer_num}/peer${peer_num}.conf"
    local i
    for ((i = 0; i < 120; i++)); do
        _sudo test -f "$conf_path" && return 0
        sleep 1
    done
    echo "Timeout: конфиг клиента не создан: ${conf_path}" >&2
    return 1
}

# Установить qrencode (если нет), вывести конфиг и QR-код между маркерами.
_wg_print_config_and_qr() {
    local conf_file="$1"
    local rendered_conf
    rendered_conf=$(_sudo sed '/^ListenPort[[:space:]]*=/d' "$conf_file" 2>/dev/null || _sudo cat "$conf_file")
    printf '\n%s\n' '--- WG-CLIENT-CONFIG-BEGIN ---'
    printf '%s\n' "$rendered_conf"
    printf '%s\n' '--- WG-CLIENT-CONFIG-END ---'
    if ! command -v qrencode >/dev/null 2>&1; then
        _sudo apt-get update -qq >/dev/null 2>&1 || true
        _sudo apt-get install -y -q qrencode >/dev/null 2>&1 || true
    fi
    if command -v qrencode >/dev/null 2>&1; then
        printf '\n%s\n' '--- WG-CLIENT-QR-BEGIN ---'
        printf '%s\n' "$rendered_conf" | qrencode -t ansiutf8 2>/dev/null || true
        printf '%s\n' '--- WG-CLIENT-QR-END ---'
    fi
}

# --- Действия -----------------------------------------------------------------------

# Установка: создать каталог, pull образа, запустить с PEERS=1, сохранить счётчик.
wg_install() {
    _sudo mkdir -p "${WG_DATA_DIR}/config"
    echo "Docker-образ: ${WG_IMAGE}"
    echo "Загрузка образа ${WG_IMAGE}..."
    _sudo docker pull "${WG_IMAGE}"
    _wg_run_container 1
    printf '1\n' | _sudo tee "$WG_PEERS_FILE" >/dev/null
    echo "Ожидание генерации конфига клиента..."
    _wg_wait_for_peer 1
    _wg_print_config_and_qr "${WG_DATA_DIR}/config/peer1/peer1.conf"
}

# Показать конфиг первого клиента из сохранённого файла.
wg_print_client() {
    local conf="${WG_DATA_DIR}/config/peer1/peer1.conf"
    if _sudo test -f "$conf"; then
        _wg_print_config_and_qr "$conf"
    else
        echo "wg-client-config: файл не найден: ${conf}" >&2
        return 1
    fi
}

# Показать конфиг клиента по номеру WG_CLIENT_NUM.
wg_print_client_by_num() {
    local num conf
    num="${WG_CLIENT_NUM:-1}"
    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 )); then
        echo "wg-client-config: некорректный номер клиента: ${num}" >&2
        return 1
    fi
    conf="${WG_DATA_DIR}/config/peer${num}/peer${num}.conf"
    if _sudo test -f "$conf"; then
        _wg_print_config_and_qr "$conf"
    else
        echo "wg-client-config: указанной конфигурации нет: client ${num}" >&2
        return 1
    fi
}

# Добавить нового клиента: перезапустить контейнер с PEERS+1, вывести конфиг нового пира.
wg_add_client() {
    local current new_num
    current=$(_wg_peers_count)
    new_num=$(( current + 1 ))
    echo "Добавление клиента ${new_num} (перезапуск контейнера с PEERS=${new_num})..."
    _wg_run_container "$new_num"
    printf '%s\n' "$new_num" | _sudo tee "$WG_PEERS_FILE" >/dev/null
    _wg_wait_for_peer "$new_num"
    printf 'WG_NEW_CLIENT_NUM=%s\n' "$new_num"
    _wg_print_config_and_qr "${WG_DATA_DIR}/config/peer${new_num}/peer${new_num}.conf"
}

# --- Точка входа --------------------------------------------------------------------
case "$WG_ACTION" in
    check)      wg_check_running ;;
    install)    wg_install ;;
    client)     wg_print_client ;;
    get_client) wg_print_client_by_num ;;
    add_client) wg_add_client ;;
    *)
        echo "WG_ACTION: неизвестное действие: ${WG_ACTION}" >&2
        exit 1
        ;;
esac
