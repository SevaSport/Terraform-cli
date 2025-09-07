#!/bin/bash

# Отключение IPv6 на удаленной машине
disable_ipv6() {
    local IPV6_DISABLE=$(yq e '.vps.ipv6_disable' "$CONFIGURATIONS")
    if [ "$IPV6_DISABLE" ]; then
        # Выполнение удаленного скрипта и получение вывода
        run_ssh_with_file "$(dirname "$BASH_SOURCE")/remote.sh"
        local result=$?

        step_name "Отключение IPv6" "$YELLOW"
        if [ $result -eq 0 ]; then
            step_status "ОК" "$GREEN"
        else
            step_status "ошибка (код: $result)" "$RED"
        fi
    fi
}

disable_ipv6