#!/bin/bash
set -euo pipefail

# Выполняется на VPS: обновление индексов, обновление пакетов, удаление лишних зависимостей (только apt, без apt-get).
run_apt_with_retry() {
    local max_attempts=2
    local attempt=1
    local sleep_sec=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if _sudo apt update -y &&
            _sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y &&
            _sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y; then
            return 0
        fi

        echo "apt attempt $attempt/$max_attempts failed" >&2
        sleep "$sleep_sec"
        attempt=$((attempt + 1))
    done

    return 1
}

run_apt_with_retry
