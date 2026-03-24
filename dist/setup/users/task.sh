#!/bin/bash

# Создание учётных записей на VPS по массиву vps.users в config.yml:
# useradd (оболочка /bin/bash), пароль (chpasswd), группа sudo при необходимости,
# копирование локального публичного ключа в authorized_keys, итоговый список в консоли.

# Проверка обязательных полей name и pass для элемента списка
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

check_user_exists() {
    local name="$1"
    if run_ssh "id -u '$name' >/dev/null 2>&1"; then
        step_status "уже существует" "$GREEN"
        return 0
    fi
    return 1
}

create_user() {
    local name="$1"
    local pass="$2"
    local home_dir="$3"

    local group_exists
    if run_ssh "getent group '$name' >/dev/null 2>&1"; then
        group_exists=true
    else
        group_exists=false
    fi

    local useradd_cmd="useradd"
    [ "$home_dir" = "true" ] && useradd_cmd="$useradd_cmd -m"

    if [ "$group_exists" = true ]; then
        useradd_cmd="$useradd_cmd -g '$name'"
    else
        useradd_cmd="$useradd_cmd -U"
    fi

    useradd_cmd="$useradd_cmd -s /bin/bash"
    useradd_cmd="$useradd_cmd '$name'"

    if run_ssh "$useradd_cmd" && run_ssh "echo '$name:$pass' | chpasswd"; then
        step_status "создан$([ "$home_dir" = "true" ] && echo " с домашней директорией")" "$GREEN"
        return 0
    else
        step_status "ошибка создания" "$RED"
        return 1
    fi
}

add_sudo_permissions() {
    local name="$1"
    local sudoer="$2"

    if [ "$sudoer" = "true" ]; then
        if run_ssh "usermod -aG sudo '$name'"; then
            message " sudo для пользователя $name" "OK" "$YELLOW" "$GREEN"
        else
            message " sudo для пользователя $name" "Ошибка" "$YELLOW" "$RED"
        fi
    fi
}

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

copy_ssh_key() {
    local name="$1"
    local allow_ssh="$2"

    if [ "$allow_ssh" = "true" ]; then
        local ssh_key_file
        ssh_key_file=$(find_ssh_key)

        if [ -n "$ssh_key_file" ] && [ -f "$ssh_key_file" ]; then
            local ssh_key_content
            ssh_key_content=$(cat "$ssh_key_file")

            step_name " копирование публичного ключа" "$YELLOW"
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
            message "Локальный публичный ключ (~/.ssh/*.pub)" "не найден" "$YELLOW" "$YELLOW"
        fi
    fi
}

apply_ssh_allow_users_policy() {
    local users_count
    local i
    local name
    local allow_ssh
    local allow_users=""
    local sudo_pass_q

    users_count=$(yq eval '.vps.users | length' "$CONFIGURATIONS")
    for ((i=0; i<users_count; i++)); do
        name=$(yq e ".vps.users[$i].name" "$CONFIGURATIONS")
        allow_ssh=$(yq e ".vps.users[$i].allow_ssh" "$CONFIGURATIONS")
        [[ -n "$name" && "$name" != "null" ]] || continue
        [[ "$allow_ssh" == "true" ]] || continue
        allow_users="${allow_users:+$allow_users }$name"
    done

    step_name "Ограничение SSH-доступа (AllowUsers)" "$YELLOW"
    if [[ -z "$allow_users" ]]; then
        step_status "нет пользователей с allow_ssh: true" "$RED"
        return 1
    fi

    sudo_pass_q=$(printf '%q' "$VPS_PASS")
    if run_ssh "printf '%s\n' $sudo_pass_q | sudo -S -p '' sh -c \"printf '%s\n' 'AllowUsers $allow_users' > /etc/ssh/sshd_config.d/10-allow-users.conf\" && printf '%s\n' $sudo_pass_q | sudo -S -p '' sshd -t && printf '%s\n' $sudo_pass_q | sudo -S -p '' systemctl restart ssh"; then
        step_status "$allow_users" "$GREEN"
        return 0
    fi
    step_status "ошибка применения" "$RED"
    return 1
}

show_all_users() {
    title "Список пользователей на удалённом сервере" "$BLUE"

    local all_users
    all_users=$(run_ssh "getent passwd | awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1}' | sort")

    local super_users=()
    local regular_users=()

    for user in $all_users; do
        if [ -n "$user" ]; then
            if run_ssh "groups '$user' | grep -q '\bsudo\b'"; then
                super_users+=("$user")
            else
                regular_users+=("$user")
            fi
        fi
    done

    for user in "${super_users[@]}"; do
        step_name " $user" "$YELLOW"
        step_status "имеет права администратора" "$GREEN"
    done

    for user in "${regular_users[@]}"; do
        step_name " $user" "$YELLOW"
        step_status "ограниченные права" "$YELLOW"
    done

    if [ ${#super_users[@]} -eq 0 ] && [ ${#regular_users[@]} -eq 0 ]; then
        step_name "Пользователи уже существуют на сервере" "$YELLOW"
        step_status "нет пользователей с UID >= 1000" "$YELLOW"
    fi
}

add_users() {
    local users_count
    local i
    users_count=$(yq eval '.vps.users | length' "$CONFIGURATIONS")

    if (( users_count > 0 )); then
        title "Создание пользователей на удалённом сервере" "$BLUE"

        for ((i=0; i<users_count; i++)); do
            local name
            local pass
            local home_dir
            local allow_ssh
            local sudoer
            name=$(yq ".vps.users[$i].name" "$CONFIGURATIONS")
            pass=$(yq ".vps.users[$i].pass" "$CONFIGURATIONS")
            home_dir=$(yq ".vps.users[$i].\"home-dir\"" "$CONFIGURATIONS")
            allow_ssh=$(yq ".vps.users[$i].allow_ssh" "$CONFIGURATIONS")
            sudoer=$(yq ".vps.users[$i].sudoer" "$CONFIGURATIONS")

            if ! validate_user_data "$name" "$pass" "$i"; then
                continue
            fi

            step_name "Пользователь $name" "$YELLOW"

            if check_user_exists "$name"; then
                continue
            fi

            if create_user "$name" "$pass" "$home_dir"; then
                add_sudo_permissions "$name" "$sudoer"
                copy_ssh_key "$name" "$allow_ssh"
            fi
        done

        if ! apply_ssh_allow_users_policy; then
            exit 1
        fi
        # После применения AllowUsers (только allow_ssh=true) переключаемся
        # на сервисного пользователя ssh для следующих шагов.
        if ! export_credentials_for_vps_user_named ssh; then
            message "Пользователь ssh в vps.users" "не найден или без пароля" "$RED" "$RED"
            exit 1
        fi

        show_all_users
    fi
}

add_users
