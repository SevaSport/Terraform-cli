#!/bin/bash

# При applications.docker в config: установка Docker Engine скриптом
# get.docker.com, если пакет docker на сервере ещё не стоит.

check_docker_installation() {
    if ! is_package_installed "docker"; then
        if run_ssh_with_file_step_result \
            "$(dirname "$BASH_SOURCE")/remote.sh" \
            "Установка Docker Engine на VPS"; then
            return 0
        fi
        return 1
    else
        message "Docker на сервере" "уже установлен" "$YELLOW" "$GREEN"
        return 0
    fi
}

show_docker_versions() {
    step_name "Проверка версии Docker" "$YELLOW"
    step_status "$(remote_docker_engine_version)" "$GREEN"

    step_name "Проверка версии Docker Compose" "$YELLOW"
    step_status "$(remote_docker_compose_v2_version)" "$GREEN"
}

setup_docker() {
    title "Установка Docker на удалённом сервере" "$BLUE"

    if check_docker_installation; then
        show_docker_versions
    else
        exit 1
    fi
}

if config_application_enabled docker; then
    setup_docker
fi
