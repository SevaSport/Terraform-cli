#!/bin/bash

# Выполняется на VPS: AmneziaWG в Docker (amneziavpn/amneziawg-go — официальный образ AWG2).
# AWG_ACTION: install | check | client | get_client | add_client
#   install    — pull образ, сгенерировать ключи/обфускацию, создать конфиг, запустить контейнер;
#                вывести клиентский конфиг + QR-код (если есть qrencode) в stdout.
#   check      — запущен ли контейнер AWG_CONTAINER.
#   client     — напечатать первый клиентский конфиг из AWG_DATA_DIR/client1.conf + QR-код.
#   get_client — напечатать клиентский конфиг по номеру AWG_CLIENT_NUM + QR-код.
#   add_client — добавить нового клиента (следующий свободный IP) + вывести конфиг и QR-код.
# AWG_PORT, AWG_PUBLIC_HOST обязательны; остальные — с умолчаниями.
set -euo pipefail

type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

AWG_ACTION="${AWG_ACTION:-install}"
AWG_CONTAINER="${AWG_CONTAINER:-amnezia-awg2}"
AWG_IMAGE="${AWG_IMAGE:-amneziavpn/amneziawg-go:latest}"
AWG_PORT="${AWG_PORT:?AWG_PORT is required}"
AWG_PUBLIC_HOST="${AWG_PUBLIC_HOST:?AWG_PUBLIC_HOST is required}"
AWG_NETWORK="${AWG_NETWORK:-10.8.0.0}"
AWG_DNS="${AWG_DNS:-1.1.1.1,1.0.0.1}"
AWG_ALLOWED_IPS="${AWG_ALLOWED_IPS:-0.0.0.0/0}"
AWG_CLIENT_NUM="${AWG_CLIENT_NUM:-1}"
AWG_DATA_DIR="${AWG_DATA_DIR:-/opt/amneziawg}"
AWG_SERVER_IFACE_IP="${AWG_SERVER_IFACE_IP:-${AWG_NETWORK%.*}.1/24}"
AWG_SUBNET="${AWG_SUBNET:-${AWG_NETWORK}/24}"

# Из значения вида «min-max» или одиночного числа выбрать случайное целое в диапазоне [min, max].
# Используется для H1-H4 клиентского конфига: сервер принимает диапазон, клиент шлёт конкретное значение.

# Сгенерировать пару ключей внутри контейнера AWG_IMAGE; вывести две строки: private public.
awg_gen_keypair() {
    echo "Docker-образ: ${AWG_IMAGE}" >&2
    _sudo docker run --rm "$AWG_IMAGE" sh -c \
        'pk=$(awg genkey 2>/dev/null || wg genkey); printf "%s\n" "$pk"; printf "%s\n" "$pk" | awg pubkey 2>/dev/null || printf "%s\n" "$pk" | wg pubkey'
}

# Проверить, запущен ли контейнер с именем AWG_CONTAINER.
awg_check_running() {
    _sudo docker ps --format '{{.Names}}' | grep -qx "${AWG_CONTAINER}"
}

# Найти следующий свободный номер клиента (client1.conf, client2.conf …).
_awg_next_client_num() {
    local num=1
    while _sudo test -f "${AWG_DATA_DIR}/client${num}.conf" 2>/dev/null; do
        num=$((num + 1))
    done
    printf '%s' "$num"
}

# Найти следующий свободный IP в подсети 10.8.0.0/24 (сервер = .1, клиенты = .2+).
_awg_next_client_ip() {
    local server_conf="${AWG_DATA_DIR}/config/wg0.conf"
    local max_octet=1
    local ip octet
    local subnet_prefix
    subnet_prefix="${AWG_SUBNET%.*}"
    while IFS= read -r ip; do
        octet="${ip%%/*}"
        octet="${octet##*.}"
        [[ "$octet" =~ ^[0-9]+$ ]] && (( octet > max_octet )) && max_octet=$octet
    done < <(_sudo grep -i '^AllowedIPs' "$server_conf" 2>/dev/null | awk '{print $3}')
    printf '%s' "${subnet_prefix}.$((max_octet + 1))"
}

# Убедиться, что qrencode установлен (устанавливает через apt если нет).
_awg_ensure_qrencode() {
    command -v qrencode >/dev/null 2>&1 && return 0
    _sudo apt-get update -qq >/dev/null 2>&1 || true
    _sudo apt-get install -y -q qrencode >/dev/null 2>&1 || true
}


# Собрать Amnezia QR payload: base64url( qCompress(JSON) ).
# Приложение Amnezia не принимает plain-text конфиг — только этот формат.
# python3 используется через хостовый бинарь (если есть) или через docker run python:3-alpine.
# wg pubkey берётся из работающего AWG-контейнера — python3 на хосте не нужен вовсе.
_awg_build_amnezia_qr_payload() {
    local conf_file="$1"

    # conf_file is root-owned 600 — read once via sudo, then work in-memory.
    local conf_content
    conf_content=$(_sudo cat "$conf_file" 2>/dev/null) || return 0
    [[ -n "$conf_content" ]] || return 0

    # Derive client pub key via the running AWG container (wg is always available there).
    local priv_key client_pub_key
    priv_key=$(printf '%s' "$conf_content" | grep -m1 'PrivateKey' | sed 's/^[^=]*=\s*//' | tr -d '[:space:]')
    client_pub_key=$(printf '%s\n' "$priv_key" \
        | _sudo docker exec -i "$AWG_CONTAINER" wg pubkey 2>/dev/null \
        | tr -d '[:space:]' || true)

    # Temp dir owned by the current user — write without sudo so chmod works.
    local tmpdir
    tmpdir=$(mktemp -d /tmp/.awg_qr_XXXXXX)
    printf '%s' "$conf_content"   > "$tmpdir/client.conf"
    printf '%s' "$client_pub_key" > "$tmpdir/pubkey"
    chmod 755 "$tmpdir"
    chmod 644 "$tmpdir/client.conf" "$tmpdir/pubkey"

    cat > "$tmpdir/gen_qr.py" << 'PYEOF'
import json, zlib, struct, base64, re, sys

conf_text      = open(sys.argv[1]).read()
client_pub_key = open(sys.argv[2]).read().strip()

def get(key):
    m = re.search(r'^' + re.escape(key) + r'\s*=\s*(.+)$', conf_text, re.MULTILINE)
    return m.group(1).strip() if m else ''

endpoint  = get('Endpoint')
host, _, port_str = endpoint.rpartition(':')
port      = int(port_str) if port_str.isdigit() else 0
dns_parts = [d.strip() for d in get('DNS').split(',')]
dns1      = dns_parts[0] if dns_parts else ''
dns2      = dns_parts[1] if len(dns_parts) > 1 else ''

client_ip_raw = get('Address').strip()
priv_key      = get('PrivateKey').strip()
allowed_ips   = [ip.strip() for ip in get('AllowedIPs').split(',') if ip.strip()]

last_config = {
    'Jc':   get('Jc'),   'Jmin': get('Jmin'), 'Jmax': get('Jmax'),
    'S1':   get('S1'),   'S2':   get('S2'),   'S3':   get('S3'),  'S4': get('S4'),
    'H1':   get('H1'),   'H2':   get('H2'),   'H3':   get('H3'),  'H4': get('H4'),
    'I1': '', 'I2': '', 'I3': '', 'I4': '', 'I5': '',
    'allowed_ips':        allowed_ips,
    'client_ip':          client_ip_raw,
    'client_priv_key':    priv_key,
    'client_pub_key':     client_pub_key,
    'clientId':           client_pub_key,
    'config':             conf_text,
    'hostName':           host,
    'mtu':                '1500',
    'persistent_keep_alive': '25',
    'port':               port,
    'psk_key':            None,
    'server_pub_key':     get('PublicKey').strip(),
}

outer = {
    'containers': [{
        'container': 'amnezia-awg',
        'awg': {
            'isThirdPartyConfig':  True,
            'last_config':         json.dumps(last_config, separators=(',', ':')),
            'port':                str(port),
            'transport_proto':     'udp',
            'protocol_version':    '2',
        },
    }],
    'defaultContainer': 'amnezia-awg',
    'description':      f'Secure WG [{host}]',
    'dns1':             dns1,
    'dns2':             dns2,
    'hostName':         host,
}

plain  = json.dumps(outer, separators=(',', ':')).encode('utf-8')
z      = zlib.compress(plain, level=9)
# Qt qCompress format: 4-byte big-endian uncompressed length + zlib stream
packed = struct.pack('>I', len(plain)) + z
print(base64.urlsafe_b64encode(packed).decode().rstrip('='), end='')
PYEOF
    chmod 644 "$tmpdir/gen_qr.py"

    local py_args=("$tmpdir/gen_qr.py" "$tmpdir/client.conf" "$tmpdir/pubkey")
    local payload=""
    if command -v python3 >/dev/null 2>&1; then
        payload=$(python3 "${py_args[@]}" 2>/dev/null || true)
    else
        # python:3-alpine (~50 MB) is cached after the first pull.
        _sudo docker pull -q python:3-alpine >/dev/null 2>&1 || true
        payload=$(_sudo docker run --rm \
            -v "$tmpdir:$tmpdir:ro" \
            python:3-alpine \
            python3 "${py_args[@]}" 2>/dev/null || true)
    fi

    rm -rf "$tmpdir"
    printf '%s' "$payload"
}

# Вывести конфиг клиента и Amnezia-совместимый QR-код в stdout.
_awg_print_config_and_qr() {
    local conf_file="$1"
    printf '\n%s\n' '--- AWG-CLIENT-CONFIG-BEGIN ---'
    _sudo cat "$conf_file"
    printf '%s\n' '--- AWG-CLIENT-CONFIG-END ---'

    _awg_ensure_qrencode
    if command -v qrencode >/dev/null 2>&1; then
        local qr_payload
        qr_payload=$(_awg_build_amnezia_qr_payload "$conf_file")
        if [[ -n "$qr_payload" ]]; then
            printf '\n%s\n' '--- AWG-CLIENT-QR-BEGIN ---'
            printf '%s' "$qr_payload" | qrencode -t ansiutf8 2>/dev/null || true
            printf '%s\n' '--- AWG-CLIENT-QR-END ---'
        fi
    fi
}

# Применить новый peer к работающему контейнеру без перезапуска (fallback — restart).
_awg_sync_peer() {
    local client_pub="$1"
    local client_ip="$2"
    _sudo docker exec "${AWG_CONTAINER}" \
        sh -c "awg set wg0 peer '${client_pub}' allowed-ips '${client_ip}/32'" \
        >/dev/null 2>&1 \
    || _sudo docker restart "${AWG_CONTAINER}" >/dev/null 2>&1 \
    || true
}

# Установить AmneziaWG: ключи, конфиг сервера, контейнер, UFW, первый клиентский конфиг.
awg_install() {
    _sudo mkdir -p "${AWG_DATA_DIR}/config"
    local subnet_prefix first_client_ip
    subnet_prefix="${AWG_SUBNET%.*}"
    first_client_ip="${subnet_prefix}.2"

    # Pull образа до генерации ключей (awg genkey работает внутри контейнера).
    echo "Docker-образ: ${AWG_IMAGE}" >&2
    _sudo docker pull "$AWG_IMAGE"

    # Серверные ключи (однократно, не перезаписываем при повторной установке).
    local server_priv server_pub
    if _sudo test -f "${AWG_DATA_DIR}/server_private.key"; then
        server_priv=$(_sudo cat "${AWG_DATA_DIR}/server_private.key")
        server_pub=$(_sudo cat "${AWG_DATA_DIR}/server_public.key")
    else
        { read -r server_priv; read -r server_pub; } < <(awg_gen_keypair)
        printf '%s' "$server_priv" | _sudo tee "${AWG_DATA_DIR}/server_private.key" > /dev/null
        printf '%s' "$server_pub"  | _sudo tee "${AWG_DATA_DIR}/server_public.key"  > /dev/null
        _sudo chmod 600 "${AWG_DATA_DIR}/server_private.key"
    fi

    # Первый клиентский ключ.
    local client_priv client_pub
    { read -r client_priv; read -r client_pub; } < <(awg_gen_keypair)

    # Случайные параметры обфускации.
    # H1-H4 — одиночные uint32 (amneziawg-go не поддерживает диапазоны и I1).
    _rnd32() { printf '%s' "$(( (RANDOM * 65536 + RANDOM) % 2147483647 + 1 ))"; }

    local s1 s2 s3 s4 h1 h2 h3 h4
    s1=$(( RANDOM % 136 + 15 ))     # 15–150
    s2=$(( RANDOM % 136 + 15 ))     # 15–150
    s3=$(( RANDOM % 46  + 5  ))     # 5–50
    s4=$(( RANDOM % 46  + 5  ))     # 5–50
    h1=$(_rnd32); h2=$(_rnd32); h3=$(_rnd32); h4=$(_rnd32)

    # Конфиг сервера (Jc/Jmin/Jmax/S1-S4/H1-H4).
    _sudo tee "${AWG_DATA_DIR}/config/wg0.conf" > /dev/null <<EOF
[Interface]
Address = ${AWG_SERVER_IFACE_IP}
ListenPort = ${AWG_PORT}
PrivateKey = ${server_priv}
PostUp = iptables -t nat -A POSTROUTING -s ${AWG_SUBNET} -o eth0 -j MASQUERADE; iptables -A INPUT -i wg0 -j ACCEPT; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
PreDown = iptables -t nat -D POSTROUTING -s ${AWG_SUBNET} -o eth0 -j MASQUERADE; iptables -D INPUT -i wg0 -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
Jc = 4
Jmin = 10
Jmax = 50
S1 = ${s1}
S2 = ${s2}
S3 = ${s3}
S4 = ${s4}
H1 = ${h1}
H2 = ${h2}
H3 = ${h3}
H4 = ${h4}

[Peer]
# client1
PublicKey = ${client_pub}
AllowedIPs = ${first_client_ip}/32
EOF
    _sudo chmod 600 "${AWG_DATA_DIR}/config/wg0.conf"

    # Запустить (или перезапустить) контейнер.
    if _sudo docker ps -a --format '{{.Names}}' | grep -qx "${AWG_CONTAINER}"; then
        _sudo docker rm -f "${AWG_CONTAINER}"
    fi
    echo "Docker-образ: ${AWG_IMAGE}" >&2
    _sudo docker run -d \
        --name "${AWG_CONTAINER}" \
        --restart unless-stopped \
        --privileged \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --sysctl net.ipv4.conf.all.src_valid_mark=1 \
        --sysctl net.ipv4.ip_forward=1 \
        -p "${AWG_PORT}:${AWG_PORT}/udp" \
        -v /lib/modules:/lib/modules \
        -v "${AWG_DATA_DIR}/config:/etc/amnezia/amneziawg" \
        "$AWG_IMAGE" \
        sh -c "awg-quick up /etc/amnezia/amneziawg/wg0.conf && sleep infinity"

    # Первый клиентский конфиг.
    # H-значения клиента должны точно совпадать с серверными.
    _sudo tee "${AWG_DATA_DIR}/client1.conf" > /dev/null <<EOF
[Interface]
PrivateKey = ${client_priv}
Address = ${first_client_ip}/32
DNS = ${AWG_DNS}
Jc = 4
Jmin = 10
Jmax = 50
S1 = ${s1}
S2 = ${s2}
S3 = ${s3}
S4 = ${s4}
H1 = ${h1}
H2 = ${h2}
H3 = ${h3}
H4 = ${h4}

[Peer]
PublicKey = ${server_pub}
Endpoint = ${AWG_PUBLIC_HOST}:${AWG_PORT}
AllowedIPs = ${AWG_ALLOWED_IPS}
PersistentKeepalive = 25
EOF
    _sudo chmod 600 "${AWG_DATA_DIR}/client1.conf"

    # Скрипт для добавления клиентов прямо на сервере (без локального проекта).
    _sudo tee /opt/amneziawg/add_client.sh > /dev/null <<EOSCRIPT
#!/bin/bash
AWG_ACTION=add_client \\
AWG_PORT=${AWG_PORT} \\
AWG_PUBLIC_HOST=${AWG_PUBLIC_HOST} \\
AWG_CONTAINER=${AWG_CONTAINER} \\
AWG_IMAGE=${AWG_IMAGE} \\
AWG_NETWORK=${AWG_NETWORK} \\
AWG_DNS=${AWG_DNS} \\
AWG_ALLOWED_IPS=${AWG_ALLOWED_IPS} \\
bash /opt/amneziawg/manage.sh
EOSCRIPT
    _sudo chmod +x /opt/amneziawg/add_client.sh

    _sudo tee /opt/amneziawg/get_client.sh > /dev/null <<EOSCRIPT
#!/bin/bash
num="\${1:-1}"
AWG_ACTION=get_client \\
AWG_CLIENT_NUM="\${num}" \\
AWG_PORT=${AWG_PORT} \\
AWG_PUBLIC_HOST=${AWG_PUBLIC_HOST} \\
AWG_CONTAINER=${AWG_CONTAINER} \\
AWG_IMAGE=${AWG_IMAGE} \\
AWG_NETWORK=${AWG_NETWORK} \\
AWG_DNS=${AWG_DNS} \\
AWG_ALLOWED_IPS=${AWG_ALLOWED_IPS} \\
bash /opt/amneziawg/manage.sh
EOSCRIPT
    _sudo chmod +x /opt/amneziawg/get_client.sh

    _awg_print_config_and_qr "${AWG_DATA_DIR}/client1.conf"
}

# Прочитать и напечатать сохранённый первый клиентский конфиг + QR-код.
awg_print_client() {
    local conf="${AWG_DATA_DIR}/client1.conf"
    if _sudo test -f "$conf"; then
        _awg_print_config_and_qr "$conf"
    else
        echo "awg-client-config: файл не найден: $conf" >&2
        return 1
    fi
}

# Прочитать и напечатать клиентский конфиг по номеру AWG_CLIENT_NUM + QR-код.
awg_print_client_by_num() {
    local num conf
    num="${AWG_CLIENT_NUM:-1}"
    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 )); then
        echo "awg-client-config: некорректный номер клиента: ${num}" >&2
        return 1
    fi
    conf="${AWG_DATA_DIR}/client${num}.conf"
    if _sudo test -f "$conf"; then
        _awg_print_config_and_qr "$conf"
    else
        echo "awg-client-config: указанной конфигурации нет: client ${num}" >&2
        return 1
    fi
}

# Добавить нового клиента: следующий свободный IP, новые ключи, конфиг + QR-код.
awg_add_client() {
    local server_conf="${AWG_DATA_DIR}/config/wg0.conf"
    if ! _sudo test -f "$server_conf"; then
        echo "awg_add_client: конфиг сервера не найден, сначала запустите install" >&2
        return 1
    fi

    # Обфускационные параметры берём из действующего конфига сервера.
    # || true защищает от set -e когда параметр отсутствует в старом конфиге.
    local jc jmin jmax s1 s2 s3 s4 h1 h2 h3 h4 i1
    jc=$(   _sudo grep -m1 '^Jc '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    jmin=$( _sudo grep -m1 '^Jmin ' "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    jmax=$( _sudo grep -m1 '^Jmax ' "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    s1=$(   _sudo grep -m1 '^S1 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    s2=$(   _sudo grep -m1 '^S2 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    s3=$(   _sudo grep -m1 '^S3 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    s4=$(   _sudo grep -m1 '^S4 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    h1=$(   _sudo grep -m1 '^H1 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    h2=$(   _sudo grep -m1 '^H2 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    h3=$(   _sudo grep -m1 '^H3 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    h4=$(   _sudo grep -m1 '^H4 '   "$server_conf" 2>/dev/null | awk '{print $3}' || true)
    # Апгрейд: Jmin/Jmax/S1/S2 если остались старые нулевые значения.
    local server_conf_updated=0
    if [[ "${jmin}" == "40" || -z "${jmin}" ]]; then
        jmin=10; _sudo sed -i "s/^Jmin = .*/Jmin = ${jmin}/" "$server_conf"; server_conf_updated=1; fi
    if [[ "${jmax}" == "70" || -z "${jmax}" ]]; then
        jmax=50; _sudo sed -i "s/^Jmax = .*/Jmax = ${jmax}/" "$server_conf"; server_conf_updated=1; fi
    if [[ "${s1}" == "0" || -z "${s1}" ]]; then
        s1=$(( RANDOM % 136 + 15 ))
        _sudo sed -i "s/^S1 = .*/S1 = ${s1}/" "$server_conf"; server_conf_updated=1; fi
    if [[ "${s2}" == "0" || -z "${s2}" ]]; then
        s2=$(( RANDOM % 136 + 15 ))
        _sudo sed -i "s/^S2 = .*/S2 = ${s2}/" "$server_conf"; server_conf_updated=1; fi
    if [[ -z "${s3}" ]]; then
        s3=$(( RANDOM % 46 + 5 ))
        _sudo sed -i "/^S2 = /a S3 = ${s3}" "$server_conf"; server_conf_updated=1; fi
    if [[ -z "${s4}" ]]; then
        s4=$(( RANDOM % 46 + 5 ))
        _sudo sed -i "/^S3 = /a S4 = ${s4}" "$server_conf"; server_conf_updated=1; fi
    # Убрать H-диапазоны и I1 если они есть — amneziawg-go их не поддерживает.
    if _sudo grep -qE '^H[1-4] = [0-9]+-[0-9]+' "$server_conf" 2>/dev/null; then
        _sudo sed -i 's/^\(H[1-4] = \)\([0-9]*\)-[0-9]*/\1\2/' "$server_conf"; server_conf_updated=1; fi
    if _sudo grep -q '^I1 ' "$server_conf" 2>/dev/null; then
        _sudo sed -i '/^I1 /d' "$server_conf"; server_conf_updated=1; fi

    if [[ "$server_conf_updated" -eq 1 ]]; then
        _sudo docker restart "${AWG_CONTAINER}" >/dev/null 2>&1 || true
    fi

    local server_pub
    server_pub=$(_sudo cat "${AWG_DATA_DIR}/server_public.key")

    local client_num client_ip
    client_num=$(_awg_next_client_num)
    client_ip=$(_awg_next_client_ip)

    # Новая пара ключей клиента.
    local client_priv client_pub
    { read -r client_priv; read -r client_pub; } < <(awg_gen_keypair)

    # Добавить Peer в server_conf (персистентно).
    _sudo tee -a "$server_conf" > /dev/null <<EOF

[Peer]
# client${client_num}
PublicKey = ${client_pub}
AllowedIPs = ${client_ip}/32
EOF

    # Применить к работающему интерфейсу без полного перезапуска.
    _awg_sync_peer "$client_pub" "$client_ip"

    # H-значения клиента должны точно совпадать с серверными.
    _sudo tee "${AWG_DATA_DIR}/client${client_num}.conf" > /dev/null <<EOF
[Interface]
PrivateKey = ${client_priv}
Address = ${client_ip}/32
DNS = ${AWG_DNS}
Jc = ${jc:-4}
Jmin = ${jmin:-10}
Jmax = ${jmax:-50}
S1 = ${s1:-15}
S2 = ${s2:-15}
S3 = ${s3:-5}
S4 = ${s4:-5}
H1 = ${h1}
H2 = ${h2}
H3 = ${h3}
H4 = ${h4}

[Peer]
PublicKey = ${server_pub}
Endpoint = ${AWG_PUBLIC_HOST}:${AWG_PORT}
AllowedIPs = ${AWG_ALLOWED_IPS}
PersistentKeepalive = 25
EOF
    _sudo chmod 600 "${AWG_DATA_DIR}/client${client_num}.conf"

    printf 'AWG_NEW_CLIENT_NUM=%s\n' "$client_num"
    _awg_print_config_and_qr "${AWG_DATA_DIR}/client${client_num}.conf"
}

case "$AWG_ACTION" in
    check)      awg_check_running ;;
    install)    awg_install ;;
    client)     awg_print_client ;;
    get_client) awg_print_client_by_num ;;
    add_client) awg_add_client ;;
    *)
        echo "AWG_ACTION: неизвестное действие: ${AWG_ACTION}" >&2
        exit 1
        ;;
esac
