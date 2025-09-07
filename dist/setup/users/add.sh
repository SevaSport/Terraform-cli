#!/bin/bash

# Функция проверки обязательных данных пользователя
validate_user_data() {
    local name="$1"
    local pass="$2"
    local index="$3"
    
    if [[ -z "$name" || -z "$pass" ]]; then
        step_name "Проверка данных пользователя $index" "$YELLOW"
        step_status "отсутствуют name или pass" "$RED"
        return 1
    fi
    return 0
}

# Функция проверки существования пользователя
check_user_exists() {
    local name="$1"
    if run_ssh "id -u '$name' >/dev/null 2>&1"; then
        step_status "уже существует" "$GREEN"
        return 0
    fi
    return 1
}

# Функция создания пользователя
create_user() {
    local name="$1"
    local pass="$2"
    local home_dir="$3"
    
    # Сначала проверяем существование группы
    local group_exists
    if run_ssh "getent group '$name' >/dev/null 2>&1"; then
        group_exists=true
    else
        group_exists=false
    fi
    
    local useradd_cmd="useradd"
    [ "$home_dir" = "true" ] && useradd_cmd="$useradd_cmd -m"
    
    if [ "$group_exists" = true ]; then
        # Если группа существует, используем флаг -g для указания существующей группы
        useradd_cmd="$useradd_cmd -g '$name'"
    else
        # Если группы нет, создаем пользователя с созданием группы
        useradd_cmd="$useradd_cmd -U"
    fi
    
    useradd_cmd="$useradd_cmd '$name'"
    
    if run_ssh "$useradd_cmd" && run_ssh "echo '$name:$pass' | chpasswd"; then
        step_status "создан$([ "$home_dir" = "true" ] && echo " с домашней директорией")" "$GREEN"
        return 0
    else
        step_status "ошибка создания" "$RED"
        return 1
    fi
}

# Функция добавления прав sudo
add_sudo_permissions() {
    local name="$1"
    local sudoer="$2"
    
    if [ "$sudoer" = "true" ]; then
        if run_ssh "usermod -aG sudo '$name'"; then
            message "Добавление прав суперпользователя" "ОК" "$YELLOW" "$GREEN"
        else
            message "Добавление прав суперпользователя" "не добавлены" "$YELLOW" "$RED"
        fi
    fi
}

# Функция поиска SSH Копирование локального SSH ключа
find_ssh_key() {
    for key_file in ~/.ssh/*.pub; do
        if [ -f "$key_file" ]; then
            echo "$key_file"
            return 0
        fi
    done
    echo ""
    return 1
}

# Функция копирования SSH ключа
copy_ssh_key() {
    local name="$1"
    local copy_id="$2"
    
    if [ "$copy_id" = "true" ]; then
        local ssh_key_file=$(find_ssh_key)
        
        if [ -n "$ssh_key_file" ] && [ -f "$ssh_key_file" ]; then
            local ssh_key_content=$(cat "$ssh_key_file")
            
            step_name "Копирование локального SSH ключа" "$YELLOW"
            if run_ssh "mkdir -p /home/$name/.ssh && \
                        echo '$ssh_key_content' | tee -a /home/$name/.ssh/authorized_keys >/dev/null && \
                        chown -R $name:$name /home/$name/.ssh && \
                        chmod 700 /home/$name/.ssh && \
                        chmod 600 /home/$name/.ssh/authorized_keys"; then
                step_status "OK" "$GREEN"
            else
                step_status "ошибка" "$RED"
            fi
        else
            message "Локальный SSH ключ" "не найден" "$YELLOW" "$YELLOW"
        fi
    fi
}

# Функция для отображения всех пользователей на удаленной машине
show_all_users() {
    title "Список пользователей на сервере" "$BLUE"
    
    # Получаем всех пользователей с UID >= 1000 (обычные пользователи)
    local all_users=$(run_ssh "getent passwd | awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1}' | sort")
    
    # Собираем пользователей с sudo правами и обычных
    local super_users=()
    local regular_users=()
    
    for user in $all_users; do
        if [ -n "$user" ]; then
            # Проверяем, есть ли пользователь в группе sudo (правильный способ)
            if run_ssh "groups '$user' | grep -q '\bsudo\b'"; then
                super_users+=("$user")
            else
                regular_users+=("$user")
            fi
        fi
    done
    
    # Выводим супер пользователей
    for user in "${super_users[@]}"; do
        step_name "- $user" "$YELLOW"
        step_status "имеет права администратора" "$GREEN"
    done
    
    # Выводим обычных пользователей
    for user in "${regular_users[@]}"; do
        step_name "- $user" "$YELLOW"
        step_status "ограниченные права" "$YELLOW"
    done
    
    # Если нет пользователей
    if [ ${#super_users[@]} -eq 0 ] && [ ${#regular_users[@]} -eq 0 ]; then
        step_name "На сервере" "$YELLOW"
        step_status "нет пользователей с UID >= 1000" "$YELLOW"
    fi
}

# Основная функция создания пользователей
add_users() {
    local users_count=$(yq eval '.vps.users | length' "$CONFIGURATIONS")
    
    if (( users_count > 0 )); then
        title "Создание пользователей на сервере" "$BLUE"
        
        for ((i=0; i<users_count; i++)); do
            local name=$(yq ".vps.users[$i].name" "$CONFIGURATIONS")
            local pass=$(yq ".vps.users[$i].pass" "$CONFIGURATIONS")
            local home_dir=$(yq ".vps.users[$i].\"home-dir\"" "$CONFIGURATIONS")
            local copy_id=$(yq ".vps.users[$i].\"ssh-copy-id\"" "$CONFIGURATIONS")
            local sudoer=$(yq ".vps.users[$i].sudoer" "$CONFIGURATIONS")
            
            # Проверяем обязательные данные
            if ! validate_user_data "$name" "$pass" "$i"; then
                continue
            fi
            
            step_name "- $name" "$YELLOW"
            
            # Проверяем существование пользователя
            if check_user_exists "$name"; then
                continue
            fi
            
            # Создаем пользователя
            if create_user "$name" "$pass" "$home_dir"; then
                # Добавляем права sudo
                add_sudo_permissions "$name" "$sudoer"
                
                # Копируем SSH ключ
                copy_ssh_key "$name" "$copy_id"
            fi
        done

        # Показываем всех пользователей на удаленной машине
        show_all_users
    fi
}

# Вызов основной функции
add_users