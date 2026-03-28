#!/bin/bash

# Выполняется на VPS: образ telegrammessenger/proxy, порт публикации из MTPROTO_HOST_PORT.
# MTPROTO_ACTION: install | check | show
# install — pull, контейнер, UFW; в stdout одна строка tg://proxy?... (лог SSH, как JSON у Outline).
# check — контейнер с именем MTPROTO_CONTAINER_NAME среди запущенных.
# show — из inspect собрать tg:// и вывести в stdout.
set -euo pipefail

type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

MTPROTO_ACTION="${MTPROTO_ACTION:-install}"
MTPROTO_CONTAINER_NAME="${MTPROTO_CONTAINER_NAME:-mtproto-proxy}"
MTPROTO_IMAGE="${MTPROTO_IMAGE:-telegrammessenger/proxy:latest}"
MTPROTO_HOST_PORT="${MTPROTO_HOST_PORT:?MTPROTO_HOST_PORT is required}"
MTPROTO_PUBLIC_HOST="${MTPROTO_PUBLIC_HOST:?MTPROTO_PUBLIC_HOST is required}"
MTPROTO_SECRET="${MTPROTO_SECRET:-}"
MTPROTO_VOLUME="${MTPROTO_VOLUME:-mtproto-proxy-data}"

print_proxy_url_line() {
    local secret="$1"
    printf '%s\n' "tg://proxy?server=${MTPROTO_PUBLIC_HOST}&port=${MTPROTO_HOST_PORT}&secret=${secret}"
}

mtproto_secret_from_inspect() {
    local cid
    cid=$(_sudo docker ps -q -f "name=${MTPROTO_CONTAINER_NAME}" 2>/dev/null | head -n1 || true)
    [[ -n "$cid" ]] || return 1
    _sudo docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$cid" 2>/dev/null | grep '^SECRET=' | head -n1 | cut -d= -f2- || true
}

mtproto_check_running() {
    _sudo docker ps --format '{{.Names}}' | grep -qx "${MTPROTO_CONTAINER_NAME}"
}

case "$MTPROTO_ACTION" in
    check)
        mtproto_check_running
        ;;
    show)
        shown_secret=$(mtproto_secret_from_inspect)
        if [[ -z "$shown_secret" ]]; then
            echo "MTProto: не удалось прочитать SECRET из контейнера" >&2
            exit 1
        fi
        print_proxy_url_line "$shown_secret"
        ;;
    install)
        secret=$MTPROTO_SECRET
        if [[ -z "$secret" ]]; then
            secret=$(openssl rand -hex 16)
        fi
        _sudo docker pull "$MTPROTO_IMAGE"
        if _sudo docker ps -a --format '{{.Names}}' | grep -qx "${MTPROTO_CONTAINER_NAME}"; then
            _sudo docker rm -f "${MTPROTO_CONTAINER_NAME}"
        fi
        _sudo docker run -d \
            --name "${MTPROTO_CONTAINER_NAME}" \
            --restart unless-stopped \
            -p "${MTPROTO_HOST_PORT}:443" \
            -e "SECRET=${secret}" \
            -v "${MTPROTO_VOLUME}:/data" \
            "$MTPROTO_IMAGE"
        _sudo ufw allow "${MTPROTO_HOST_PORT}/tcp" comment 'MTProto proxy' 2>/dev/null || true
        print_proxy_url_line "$secret"
        ;;
    *)
        echo "MTPROTO_ACTION: неизвестное действие: ${MTPROTO_ACTION}" >&2
        exit 1
        ;;
esac
