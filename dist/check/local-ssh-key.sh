#!/bin/bash

# Локально: SSH-клиент, каталог ~/.ssh, публичные ключи (или генерация
# RSA 4096), очистка known_hosts для IP VPS при повторной установке ОС.

title "Проверка SSH-клиента и ключей доступа" "$BLUE"

# Генерация пары ключей, если пользователь согласится на интерактив ssh-keygen
generate_ssh_keys() {
    message "Генерация пары ключей RSA 4096" "запуск ssh-keygen" "$YELLOW" "$CYAN"
    ssh-keygen -t rsa -b 4096
    if [ $? -eq 0 ]; then
        pub_keys=$(ls ~/.ssh/*.pub 2> /dev/null)
        for key in $pub_keys; do
            message "Публичный ключ $key" "OK" "$YELLOW" "$GREEN"
        done
    else
        message "Генерация пары ключей RSA 4096" "ошибка" "$YELLOW" "$RED"
        exit 1
    fi
}

# Проверка, что в системе есть ssh-клиент
if command -v ssh &>/dev/null; then
    message "SSH-клиент в системе" "OK" "$YELLOW" "$GREEN"
else
    message "SSH-клиент в системе" "не найден, пробуем установить" "$YELLOW" "$CYAN"
    if [ "$OS" == "macos" ]; then
        brew install openssh &> /dev/null
    elif [ "$OS" == "ubuntu" ]; then
        sudo apt install -y openssh-client &> /dev/null
    fi
    if [ $? -eq 0 ]; then
        message "Пакет OpenSSH (клиент)" "установлен" "$YELLOW" "$GREEN"
    else
        message "Пакет OpenSSH (клиент)" "ошибка установки" "$YELLOW" "$RED"
        exit 1
    fi
fi
#----------
# Каталог ~/.ssh и хотя бы один публичный ключ *.pub (иначе генерация)
step_name "Проверка каталога ~/.ssh для ключей" "$YELLOW"
if [ ! -d ~/.ssh ]; then
    step_status "не найден" "$RED"
    generate_ssh_keys
else
    step_status "OK" "$GREEN"
    # Перебираем публичные ключи
    pub_keys=$(ls ~/.ssh/*.pub 2> /dev/null)

    if [ -z "$pub_keys" ]; then
        message "Публичные ключи ~/.ssh/*.pub" "не найдены" "$YELLOW" "$RED"
        generate_ssh_keys
    else
        for key in $pub_keys; do
            message "Публичный ключ $key" "OK" "$YELLOW" "$GREEN"
        done
    fi
fi

clear_known_hosts_for_vps() {
    local silent="$1"
    local known_hosts_file="$HOME/.ssh/known_hosts"
    local port
    local removed=0

    if [ -f "$known_hosts_file" ]; then
        # Удаляем запись для IP (включая hashed known_hosts формат).
        if ssh-keygen -R "$VPS_IP" -f "$known_hosts_file" >/dev/null 2>&1; then
            removed=1
        fi

        # Удаляем записи формата [ip]:port для всех кандидатных SSH-портов.
        while IFS= read -r port; do
            [[ -n "$port" ]] || continue
            if ssh-keygen -R "[$VPS_IP]:$port" -f "$known_hosts_file" >/dev/null 2>&1; then
                removed=1
            fi
        done < <(ssh_port_candidates 2>/dev/null)

        # Резервный путь: явная чистка текстовых строк с IP (если они не hashed).
        if grep -q "$VPS_IP" "$known_hosts_file" 2>/dev/null; then
            sed -i.bak "/$VPS_IP/d" "$known_hosts_file"
            removed=1
        fi
    fi

    if [ "$removed" -eq 1 ]; then
        if [ -z "$silent" ]; then
            step_name "Очистка known_hosts для $VPS_IP" "$YELLOW"
            step_status "запись удалена" "$GREEN"
        fi
    else
        if [ -z "$silent" ]; then
            step_name "Очистка known_hosts для $VPS_IP" "$YELLOW"
            step_status "запись не найдена" "$YELLOW"
        fi
    fi
}

# Наличие записи помечаем, но удаляем только при реальной неудаче подключений (см. ssh-connection.sh).
step_name "Найден $VPS_IP в ~/.ssh/known_hosts" "$YELLOW"
if [ -f ~/.ssh/known_hosts ] && grep -q "$VPS_IP" ~/.ssh/known_hosts; then
    step_status "найден" "$YELLOW"
    export KNOWN_HOSTS_FOUND=1
else
    step_status "отсутствует" "$GREEN"
    export KNOWN_HOSTS_FOUND=0
fi
