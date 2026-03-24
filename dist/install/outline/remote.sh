#!/bin/bash

# Выполняется на VPS (подключается через run_ssh_bash из ПК).
# Управление: OUTLINE_ACTION — download | check | install | payload.
#   download — скачать официальный install_server.sh; check — есть ли контейнер Outline;
#   install — установить сервер (нужны OUTLINE_API_PORT, OUTLINE_KEYS_PORT); payload — одна строка JSON для Outline Manager.
# Прочие переменные: OUTLINE_INSTALLER_PATH (путь к install_server.sh), OUTLINE_CONTAINER_PATTERN (для check, подстрока в имени образа).
set -euo pipefail

type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

OUTLINE_ACTION="${OUTLINE_ACTION:-download}"
OUTLINE_INSTALLER_PATH="${OUTLINE_INSTALLER_PATH:-/tmp/outline.sh}"

# Скачать с GitHub официальный install_server.sh Outline и сделать файл исполняемым на сервере.
# Параметры: нет (путь — OUTLINE_INSTALLER_PATH). Возврат: код последней команды (wget/chmod).
download_installer() {
    wget https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh -O "$OUTLINE_INSTALLER_PATH"
    _sudo chmod +x "$OUTLINE_INSTALLER_PATH"
}

# Проверить, что среди запущенных контейнеров есть образ, в имени которого встречается заданная подстрока (типично — outline/shadowbox).
# Параметры: нет (подстрока — OUTLINE_CONTAINER_PATTERN, по умолчанию outline). Возврат: 0 если grep нашёл совпадение в выводе docker ps.
check_outline_container() {
    local pattern="${OUTLINE_CONTAINER_PATTERN:-outline}"
    _sudo docker ps --format '{{.Image}}' | grep -qi "$pattern"
}

# Запустить официальный установщик Outline с портами API и доступа по ключам из переменных окружения.
# Параметры: нет (обязательны OUTLINE_API_PORT и OUTLINE_KEYS_PORT; при отсутствии исполняемого файла вызывается загрузка установщика). Возврат: код установщика.
install_outline() {
    local api_port="${OUTLINE_API_PORT:?OUTLINE_API_PORT is required}"
    local keys_port="${OUTLINE_KEYS_PORT:?OUTLINE_KEYS_PORT is required}"

    [ -x "$OUTLINE_INSTALLER_PATH" ] || download_installer
    # Запускаем через bash, чтобы не зависеть от execute-бита/noexec.
    _sudo bash "$OUTLINE_INSTALLER_PATH" --api-port "$api_port" --keys-port "$keys_port"
}

# Из потока данных вытащить строки, похожие на однострочный JSON доступа Outline (apiUrl и certSha256 из 64 hex-символов).
# Параметры: данные на stdin. Возврат: совпадения на stdout (может быть несколько строк); при отсутствии — пусто.
extract_outline_access_json() {
    grep -aEo '\{"apiUrl":"https://[^"]+","certSha256":"[A-Fa-f0-9]{64}"\}|\{"certSha256":"[A-Fa-f0-9]{64}","apiUrl":"https://[^"]+"\}|\{"apiUrl":"http://[^"]+","certSha256":"[A-Fa-f0-9]{64}"\}|\{"certSha256":"[A-Fa-f0-9]{64}","apiUrl":"http://[^"]+"\}' 2>/dev/null || true
}

# Обойти все контейнеры (включая остановленные) и искать в их логах строку JSON доступа Outline.
# Параметры: нет. Возврат: 0 и JSON на stdout при первом нахождении; 1 если нигде не найдено.
payload_from_all_container_logs() {
    local cid
    local payload=""
    for cid in $(_sudo docker ps -aq 2>/dev/null); do
        payload=$(_sudo docker logs "$cid" 2>&1 | extract_outline_access_json | tail -n1 || true)
        [[ -n "$payload" ]] && printf '%s' "$payload" && return 0
    done
    return 1
}

# Прочитать из запущенных контейнеров типичные пути access.txt (в приоритете shadowbox, каждый id только раз) и вытащить JSON.
# Параметры: нет. Возврат: 0 и строка JSON на stdout при успехе; 1 если ни в одном контейнере не найдено.
payload_from_docker_exec_access_files() {
    local cid
    local payload
    local seen=""
    for cid in $(_sudo docker ps -q --filter "name=shadowbox" 2>/dev/null) $(_sudo docker ps -q 2>/dev/null); do
        [[ -n "$cid" ]] || continue
        [[ " $seen " == *" $cid "* ]] && continue
        seen+=" $cid"
        payload=$(
            {
                _sudo docker exec "$cid" sudo sh -c \
                    "sudo cat /opt/outline/access.txt 2>/dev/null || \
                     sudo cat /root/shadowbox/access.txt 2>/dev/null || \
                     sudo cat /var/lib/outline/access.txt 2>/dev/null || \
                     cat /opt/outline/access.txt 2>/dev/null || \
                     cat /root/shadowbox/access.txt 2>/dev/null || \
                     cat /var/lib/outline/access.txt 2>/dev/null || true" 2>/dev/null || true
            } | extract_outline_access_json | tail -n1 || true
        )
        [[ -n "$payload" ]] && printf '%s' "$payload" && return 0
    done
    return 1
}

# Собрать JSON для Outline Manager из переменных окружения контейнера shadowbox, hostname из persisted-state и отпечатка сертификата.
# Параметры: нет (ищет контейнер по имени или образу outline/shadowbox). Возврат: 0 и одна строка JSON на stdout; 1 при нехватке данных или openssl.
payload_from_shadowbox_runtime() {
    local cid api_port api_prefix cert_file host cert_sha
    cid=$(_sudo docker ps -q --filter "name=shadowbox" 2>/dev/null | head -n1 || true)
    if [[ -z "$cid" ]]; then
        local c
        for c in $(_sudo docker ps -q 2>/dev/null); do
            if _sudo docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null | grep -qi 'outline/shadowbox'; then
                cid=$c
                break
            fi
        done
    fi
    [[ -z "$cid" ]] && return 1

    local inspect_env
    inspect_env=$(_sudo docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$cid" 2>/dev/null || true)
    api_port=$(printf '%s\n' "$inspect_env" | grep '^SB_API_PORT=' | head -n1 | cut -d= -f2-)
    api_prefix=$(printf '%s\n' "$inspect_env" | grep '^SB_API_PREFIX=' | head -n1 | cut -d= -f2-)
    cert_file=$(printf '%s\n' "$inspect_env" | grep '^SB_CERTIFICATE_FILE=' | head -n1 | cut -d= -f2-)
    [[ -n "$api_port" && -n "$api_prefix" && -n "$cert_file" ]] || return 1

    host=$(
        _sudo docker exec "$cid" sh -c \
            "sed -n 's/.*\"hostname\":\"\\([^\"]*\\)\".*/\\1/p' /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null" \
            | head -n1 || true
    )
    [[ -z "$host" ]] && host=$(_sudo docker exec "$cid" sh -c 'hostname 2>/dev/null' || true)
    [[ -z "$host" ]] && return 1

    cert_sha=$(
        _sudo docker exec -e CF="$cert_file" "$cid" sh -c 'cat "$CF" 2>/dev/null' \
            | openssl x509 -outform der 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $NF}' | tr '[:lower:]' '[:upper:]'
    ) || true
    if [[ -z "$cert_sha" || ${#cert_sha} -ne 64 ]]; then
        cert_sha=$(
            _sudo docker exec -e CF="$cert_file" "$cid" sh -c \
                'cat "$CF" 2>/dev/null | openssl x509 -outform der 2>/dev/null | openssl dgst -sha256 2>/dev/null' \
                | awk '{print $NF}' | tr '[:lower:]' '[:upper:]'
        ) || true
    fi
    [[ -n "$cert_sha" && ${#cert_sha} -eq 64 ]] || return 1

    printf '{"apiUrl":"https://%s:%s/%s","certSha256":"%s"}\n' "$host" "$api_port" "$api_prefix" "$cert_sha"
    return 0
}

# Найти и напечатать одну строку JSON доступа (файлы на хосте → exec в контейнеры → сборка из shadowbox → grep по /opt/outline → логи контейнеров).
# Параметры: нет. Возврат: 0 и JSON на stdout при успехе; 1 и сообщение на stderr если нигде не найдено.
print_outline_payload() {
    local payload=""
    local f
    local cid

    for f in /opt/outline/access.txt /root/shadowbox/access.txt /var/lib/outline/access.txt; do
        if _sudo test -f "$f"; then
            payload=$(_sudo cat "$f" 2>/dev/null | extract_outline_access_json | tail -n1 || true)
            [[ -n "$payload" ]] && break
        fi
    done

    if [[ -z "$payload" ]]; then
        payload=$(payload_from_docker_exec_access_files || true)
    fi

    if [[ -z "$payload" ]]; then
        payload=$(payload_from_shadowbox_runtime || true)
    fi

    if [[ -z "$payload" ]] && _sudo test -d /opt/outline; then
        payload=$(_sudo sh -c 'grep -Rha "apiUrl" /opt/outline 2>/dev/null' | extract_outline_access_json | tail -n1 || true)
    fi

    if [[ -z "$payload" ]]; then
        cid=$(_sudo docker ps -aq --filter "name=shadowbox" 2>/dev/null | head -n1 || true)
        [[ -z "$cid" ]] && cid=$(_sudo docker ps -aq --filter "name=outline" 2>/dev/null | head -n1 || true)
        [[ -z "$cid" ]] && cid=$(_sudo docker ps -q --filter "ancestor=quay.io/outline/shadowbox" 2>/dev/null | head -n1 || true)
        if [[ -n "$cid" ]]; then
            payload=$(_sudo docker logs "$cid" 2>&1 | extract_outline_access_json | tail -n1 || true)
        fi
    fi

    if [[ -z "$payload" ]]; then
        payload=$(payload_from_all_container_logs || true)
    fi

    if [[ -n "$payload" ]]; then
        printf '%s\n' "$payload"
        return 0
    fi
    echo "outline-access-json: не найден (хост /opt/outline, docker exec access.txt, shadowbox SB_API_*, логи контейнеров)" >&2
    return 1
}

case "$OUTLINE_ACTION" in
    download)
        download_installer
        ;;
    check)
        check_outline_container
        ;;
    install)
        install_outline
        ;;
    payload)
        print_outline_payload
        ;;
    *)
        echo "Unknown OUTLINE_ACTION: $OUTLINE_ACTION" >&2
        exit 2
        ;;
esac
