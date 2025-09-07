#!/bin/bash

# Функция загрузки установщика Outline
load_outline_installer() {
    step_name "Загрузка установщика Outline" "$YELLOW"
    
    run_ssh_with_file "$(dirname "$BASH_SOURCE")/remote.sh" \
        > "$LOGS_DIR/outline-install.log" \
        2> "$LOGS_DIR/outline-error.log"
    local result=$?
    
    if [ $result -eq 0 ]; then
        step_status "ОК" "$GREEN"
    else
        step_status "ошибка (код: $result)" "$RED"
    fi
    return $result
}

# Функция установки Outline
install_outline() {
    message "Установка Outline" "" "$YELLOW"
    
    local outline_api_port=$(yq e '.vps.applications.outline.port.api' "$CONFIGURATIONS")
    local outline_keys_port=$(yq e '.vps.applications.outline.port.keys' "$CONFIGURATIONS")
    
    run_ssh "./outline.sh --api-port $outline_api_port --keys-port $outline_keys_port" \
        >> >(tee "$LOGS_DIR/outline-install.log") \
        2>> >(tee "$LOGS_DIR/outline-error.log" >&2)
    
    local result=$?
    if [ $result -eq 0 ]; then
        message "Установка Outline" "ОК" "$YELLOW" "$GREEN"
    else
        message "Установка Outline" "ошибка (код: $result)" "$YELLOW" "$RED"
    fi
    return $result
}

# Функция проверки необходимости установки Outline
check_outline_requirements() {
    # Проверка Docker
    if ! is_package_installed "docker"; then
        message "Docker" "не установлен" "$YELLOW" "$YELLOW"
        return 1
    fi
    
    # Проверка контейнера Outline
    if ! is_container_running "outline"; then
        message "Outline container" "не найден" "$YELLOW" "$YELLOW"
        return 1
    fi
    
    return 0
}

# Основная функция установки Outline
setup_outline() {
    title "Установка Outline" "$BLUE"
    
    if ! check_outline_requirements; then
        if load_outline_installer; then
            install_outline
        else
            message "Установка Outline" "прервана из-за ошибок загрузки" "$RED" "$RED"
            exit 1
        fi
    else
        message "Outline" "уже установлен и запущен" "$YELLOW" "$GREEN"
    fi
}

# Проверка наличия ключа 'applications.outline' и запуск установки
if yq eval '.vps.applications | has("outline")' "$CONFIGURATIONS" > /dev/null 2>&1; then
    setup_outline
fi