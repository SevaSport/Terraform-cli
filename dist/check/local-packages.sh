#!/bin/bash

# Убеждаемся, что на управляющей машине есть sshpass (копирование ключа по паролю) и yq (разбор YAML).

title "Проверка локальных утилит (sshpass, yq)" "$BLUE"

# Список пакетов, которые необходимо установить локально
request_packeges=(sshpass yq)

# Пытаемся поставить недостающий пакет через менеджер ОС; на Windows — только сообщение (ручная установка)
install_package() {
    local package_name="$1"
    if [ "$OS" == "macos" ]; then
        message "$package_name не найден и будет установлен через Homebrew" "" "$YELLOW"

        # Проверяем, установлен ли Homebrew
        if command -v brew &> /dev/null; then
            # Устанавливаем $package_name
            step_name "$package_name" "$YELLOW"
            brew install $package_name &> /dev/null
            if [ $? -eq 0 ]; then
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
    elif [ "$OS" == "ubuntu" ]; then
        message "$package_name не найден и будет установлен через APT" "" "$YELLOW"

        # Обновляем списки пакетов
        sudo apt update &> /dev/null

        # Устанавливаем $package_name
        step_name "$package_name" "$YELLOW"
        sudo apt install -y $package_name &> /dev/null
        if [ $? -eq 0 ]; then
            step_status "Установлен" "$GREEN"
        else
            step_status "Ошибка" "$RED"
            exit 1
        fi
    elif [ "$OS" == "windows" ]; then
        message "$package_name не найден" "Установите sshpass и yq вручную (Chocolatey, Scoop, либо запускайте скрипт из WSL/Ubuntu — см. spec.md)" "$RED" "$RED"
        exit 1
    else
        message "$package_name" "автоустановка для этой ОС не настроена (см. spec.md)" "$RED" "$RED"
        exit 1
    fi
}

# Обход списка: уже в PATH — пропуск, иначе установка или выход с ошибкой
for package in "${request_packeges[@]}"; do
    if command -v $package &> /dev/null; then
        message "$package" "OK" "$YELLOW" "$GREEN"
    else
        install_package $package
    fi
done
