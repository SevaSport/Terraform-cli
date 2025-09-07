#!/bin/bash

# Установка пакета
install_package() {
    local package="$1"
    run_ssh "sudo apt install -y '$package' > /dev/null 2>&1"
}

# Список приложений по умолчанию
packages=$(yq eval '.vps.packages[]' "$CONFIGURATIONS")

# Проверка, что список не пустой
if [ -n "$packages" ]; then
    title "Установка запрошенных пакетов" "$BLUE"
    
    # Устанавливаем по одному пакету
    for app in $packages; do
        step_name "Установка $app" "$YELLOW"

        # Проверка, что пакет установлен
        if is_package_installed "$app"; then
            step_status "ОК" "$GREEN"
            continue
        fi

        if install_package "$app"; then
            step_status "установлен" "$GREEN"
        else
            local result=$?
            step_status "ошибка (код: $result)" "$RED"
        fi
    done
else
    message "Устанавливаемые пакеты" "не заданы" "$YELLOW" "$GREEN"
fi
