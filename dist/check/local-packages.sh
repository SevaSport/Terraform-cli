#!/bin/bash

# Убеждаемся, что на управляющей машине есть sshpass (копирование ключа по паролю) и yq (разбор YAML).

title "Проверка локальных утилит (sshpass, yq)" "$BLUE"

# Список пакетов, которые необходимо установить локально
required_packages=(sshpass yq)

# Пытаемся поставить недостающий пакет через менеджер ОС; на Windows — только сообщение (ручная установка)
install_package() {
    local package_name="$1"
    if [[ "$OS" == "macos" ]]; then
        message "$package_name не найден и будет установлен через Homebrew" "" "$YELLOW"

        if command -v brew &> /dev/null; then
            step_name "$package_name" "$YELLOW"
            if brew install "$package_name" &> /dev/null; then
                step_status "Установлен" "$GREEN"
            else
                step_status "Ошибка" "$RED"
                exit 1
            fi
        else
            message "Homebrew не установлен" "установите Homebrew, чтобы продолжить" "$RED" "$RED"
            message "Инструкция и команда установки" "https://brew.sh" "$BLUE" "$YELLOW"
            exit 1
        fi
    elif [[ "$OS" == "ubuntu" ]]; then
        message "$package_name не найден и будет установлен через APT" "" "$YELLOW"

        sudo apt update &> /dev/null

        step_name "$package_name" "$YELLOW"
        if sudo apt install -y "$package_name" &> /dev/null; then
            step_status "Установлен" "$GREEN"
        else
            step_status "Ошибка" "$RED"
            exit 1
        fi
    elif [[ "$OS" == "windows" ]]; then
        message "$package_name не найден" "Установите sshpass и yq вручную (Chocolatey, Scoop, либо запускайте скрипт из WSL/Ubuntu — см. spec.md)" "$RED" "$RED"
        exit 1
    else
        message "$package_name" "автоустановка для этой ОС не настроена (см. spec.md)" "$RED" "$RED"
        exit 1
    fi
}

# Обход списка: уже в PATH — пропуск, иначе установка или выход с ошибкой
for package in "${required_packages[@]}"; do
    if command -v "$package" &> /dev/null; then
        message "$package" "ОК" "$YELLOW" "$GREEN"
    else
        install_package "$package"
    fi
done
