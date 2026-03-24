#!/bin/bash

# По списку vps.packages[] в config.yml ставит пакеты на VPS через apt;
# уже установленные пропускает.

install_config_packages() {
    local packages
    local app
    local result

    packages=$(yq eval '.vps.packages[]' "$CONFIGURATIONS")

    if [ -n "$packages" ]; then
        title "Установка пакетов из списка config.yml" "$BLUE"

        for app in $packages; do
            step_name "Установка $app" "$YELLOW"

            if is_package_installed "$app"; then
                step_status "ОК" "$GREEN"
                continue
            fi

            if apt_install_package_remote "$app"; then
                step_status "установлен" "$GREEN"
            else
                result=$?
                step_status "ошибка (код: $result)" "$RED"
            fi
        done
    else
        message "Список vps.packages в config" "пуст" "$YELLOW" "$GREEN"
    fi
}

install_config_packages
