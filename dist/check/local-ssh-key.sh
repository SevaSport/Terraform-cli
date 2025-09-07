#!/bin/bash

title "Проверка наличия ssh клиента и ключей" "$BLUE"

generate_ssh_keys() {
    message "Создается ключ" "$YELLOW"
    ssh-keygen -t rsa -b 4096
    if [ $? -eq 0 ]; then
        pub_keys=$(ls ~/.ssh/*.pub 2> /dev/null)
        for key in $pub_keys; do
            message "Ключ $key" "OK" "$YELLOW" "$GREEN"
        done
    else
        message "Создание ssh ключа" "Ошибка" "$YELLOW" "$RED"
        exit 1
    fi
}

# Проверка, что в системе есть ssh-клиент
if command -v ssh &>/dev/null; then
    message "SSH клиент" "OK" "$YELLOW" "$GREEN"
else
    message "SSH клиент" "не установлен" "$YELLOW" "$GREEN"
    if [ "$OS" == "macos" ]; then
        brew install openssh &> /dev/null
    elif [ "$OS" == "ubuntu" ]; then
        sudo apt-get install openssh-client -y  &> /dev/null
    fi
    if [ $? -eq 0 ]; then
        message "openssh" "Установлен" "$YELLOW" "$GREEN"
    else
        message "openssh" "Ошибка" "$YELLOW" "$RED"
        exit 1
    fi
fi

# Проверка, что в локально ОС есть публичные ключи
if [ ! -d ~/.ssh ]; then
    message "Директория ~/.ssh/" "не найдена" "$YELLOW" "$RED"
    generate_ssh_keys
else
    message "Директория ~/.ssh/" "OK" "$YELLOW" "$GREEN"
    # Перебираем публичные ключи
    pub_keys=$(ls ~/.ssh/*.pub 2> /dev/null)

    if [ -z "$pub_keys" ]; then
        message "Директория ~/.ssh/*.pub" "не найдены" "$YELLOW" "$RED"
        generate_ssh_keys
    else
        for key in $pub_keys; do
            message "Ключ $key" "OK" "$YELLOW" "$GREEN"
        done
    fi
fi

# Проверка, что ранее не подключались к данному IP
if grep -q "$VPS_IP" ~/.ssh/known_hosts; then
    message "Поиск $VPS_IP в ~/.ssh/known_hosts" "найдена" "$YELLOW" "$YELLOW"
    # Если найдера запись, значит уже ранее подключались к данному серверу.
    # Если ОС на сервере была переустановлена - это вызовет ошибку.
    # Правильнее удалить эту запись, и записать заного.
    sed -i.bak "/$VPS_IP/d" ~/.ssh/known_hosts
    message "Удаление $VPS_IP из ~/.ssh/known_hosts" "удалена" "$YELLOW" "$GREEN"
else
    message "Запись $VPS_IP в ~/.ssh/known_hosts" "не найдена" "$YELLOW" "$GREEN"
fi

