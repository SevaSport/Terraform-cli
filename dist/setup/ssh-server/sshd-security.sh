#!/bin/bash

# Функция для замены строки в sshd_config
change_config() {
    local file="$1"
    local param="$2"
    local value="$3"

    # Если параметр существует и закомментирован - расскоментировать и заменить
    if grep -q "^#\s*${param}" "$file"; then
        sudo sed -i "s/^#\s*${param}.*/${param} ${value}/" "$file"
        echo -e "${GREEN}${param} был закомментирован и обновлен на ${value}.${NC}"
    # Если параметр существует и не закомментирован - заменить его
    elif grep -q "^${param}" "$file"; then
        sudo sed -i "s/^${param}.*/${param} ${value}/" "$file"
        echo -e "${GREEN}${param} обновлен на ${value}.${NC}"
    # Если параметра нет - добавить его
    else
        echo "${param} ${value}" | sudo tee -a "$file" > /dev/null
        echo -e "${GREEN}${param} добавлен как ${value}.${NC}"
    fi
}

secure_ssh() {
    local config_file="/etc/ssh/sshd_config"
    local port="$1"

    echo -e "${BLUE}Обновляем конфигурации SSH в файле ${config_file} ${NC}"
    # Отключение авторизации как root
    echo -e "${YELLOW}Отключение авторизации как root...${NC}"
    change_config ${config_file} "PermitRootLogin" "no"

    # Отключение авторизации по логину и паролю
    echo -e "${YELLOW}Отключение авторизации по логину и паролю...${NC}"
    change_config ${config_file} "PasswordAuthentication" "no"

    # Изменияем стандартный порт
    echo -e "${YELLOW}Изменяем порт по умолчанию...${NC}"
    change_config ${config_file} "Port" "${port}"

    # Перезагрузка SSH службы
    #echo -e "${YELLOW}Перезапуск SSH службы...${NC}"
    #if sudo systemctl restart sshd; then
    #    echo -e "${GREEN}SSH служба успешно перезапущена.${NC}"
    #else
    #    echo -e "${RED}Ошибка при перезапуске SSH службы.${NC}"
    #fi
}

initial_update() {
    # Установка приложений по умолчанию
    DEFAULT_APPS=$(yq e '.vps.applications.default[]' $CONFIGURATIONS)
    echo -e "${YELLOW}Установка стандартных приложений...${NC}"
    sudo apt update
    for app in $DEFAULT_APPS; do
        echo -e "${YELLOW}Установка $app...${NC}"
        if sudo apt install -y $app; then
            echo -e "${GREEN}$app успешно установлен.${NC}"
        else
            echo -e "${RED}Ошибка при установке $app.${NC}"
        fi
    done
    echo -e "${YELLOW}Стандартные приложения установлены.${NC}"
}

secure_ssh 60022
