#!/bin/bash

# Основная SSH функция
run_ssh() {
    local command="$1"
    ssh -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "$command"
}

# SSH функция с передачей локального файла
run_ssh_with_file() {
    local file="$1"
    ssh -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "bash -s" < "$file"
}

# SSH функция с выполнением удаленного скрипта
run_remote_script() {
    local script="$1"
    local args="$2"
    run_ssh "$script $args"
}

# Проверка установленного пакета
is_package_installed() {
    local package="$1"
    run_ssh "dpkg -l | grep '$package' > /dev/null 2>&1"
}

# Проверка работающего Docker контейнера
is_container_running() {
    local container_name="$1"
    run_ssh "docker ps --format '{{.Image}}' | grep -i '$container_name'"
}
