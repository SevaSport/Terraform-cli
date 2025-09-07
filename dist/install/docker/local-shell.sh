#!/bin/bash

# Получение версии Docker
get_docker_version() {
    run_ssh "docker --version 2>/dev/null" | sed -E 's/[^0-9.]+([0-9.]+).*/\1/'
}

# Получение версии Docker Compose
get_compose_version() {
    run_ssh "docker compose version 2>/dev/null" | sed -E 's/[^0-9.]+([0-9.]+).*/\1/'
}

# Функция проверки установки Docker
check_docker_installation() {
    if ! is_package_installed "docker"; then
        # Выполнение удаленного скрипта установки Docker
        run_ssh_with_file "$(dirname "$BASH_SOURCE")/remote.sh" \
            1> "$LOGS_DIR/docker-install.log" \
            2> "$LOGS_DIR/docker-error.log"
        local result=$?

        step_name "Установка Docker" "$YELLOW"
        if [ $result -eq 0 ]; then
            step_status "ОК" "$GREEN"
            return 0
        else
            step_status "ошибка (код: $result)" "$RED"
            return 1
        fi
    else
        message "Статус" "установлена" "$YELLOW" "$GREEN"
        return 0
    fi
}

# Функция отображения версий Docker
show_docker_versions() {
    step_name "Версия Docker" "$YELLOW"
    local docker_version=$(get_docker_version)
    step_status "$docker_version" "$GREEN"

    step_name "Версия Docker Compose" "$YELLOW"
    local compose_version=$(get_compose_version)
    step_status "$compose_version" "$GREEN"
}

# Основная функция установки Docker
setup_docker() {
    title "Установка Docker" "$BLUE"
    
    if check_docker_installation; then
        show_docker_versions
    else
        exit 1
    fi
}

# Проверка существования ключа 'applications.docker' и запуск установки
if yq eval '.vps.applications | has("docker")' "$CONFIGURATIONS" > /dev/null 2>&1; then
    setup_docker
fi