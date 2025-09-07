#!/bin/bash

title "Проверка необходимых локальных пакетов" "$BLUE"

# Список пакетов, которые необходимо установить локально
request_packeges=(sshpass yq)

# Устанавливает запрашиваемый пакет
install_package() {
    local package_name="$1"
    # Устанавливаем $package_name в зависимости от ОС
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
            echo -e "${RED}Homebrew не установлен. Установите Homebrew, чтобы продолжить.${NC}"
            echo -e "${BLUE}Вы можете установить Homebrew, выполнив следующую команду:${NC}"
            echo -e "${YELLOW}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
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
    fi
}

# Проверка всех необходимых пакетов
for package in "${request_packeges[@]}"; do
    if command -v $package &> /dev/null; then
        message "$package" "OK" "$YELLOW" "$GREEN"
    else
        install_package $package
    fi
done
