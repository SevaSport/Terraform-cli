#!/bin/bash

# Если в config включено отключение IPv6 — правки sysctl на сервере
# (см. remote.sh в этой папке).
disable_ipv6() {
    local IPV6_DISABLE
    IPV6_DISABLE=$(yq e '(.vps."ipv6-disable" // .vps.ipv6_disable // false)' "$CONFIGURATIONS")
    if [ "$IPV6_DISABLE" = "true" ]; then
        run_ssh_with_file_step_result "$(dirname "$BASH_SOURCE")/remote.sh" \
            "Отключение IPv6 на сервере"
    fi
}

disable_ipv6
