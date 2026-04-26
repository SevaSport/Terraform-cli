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

# Устанавливает пароль пользователю через chpasswd, передавая учётные данные
# через stdin SSH-сессии (не через аргумент команды, чтобы пароль не светился в ps aux).
_set_remote_user_password() {
    local name="$1" pass="$2"
    local tmpscript rc
    tmpscript=$(mktemp)
    printf 'printf "%%s\\n" "${USER_NAME}:${USER_PASS}" | _sudo chpasswd\n' > "$tmpscript"
    run_ssh_bash \
        "$(printf 'export USER_NAME=%q USER_PASS=%q' "$name" "$pass")" \
        "$tmpscript"
    rc=$?
    rm -f "$tmpscript"
    return "$rc"
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

    if run_ssh "$useradd_cmd" && _set_remote_user_password "$name" "$pass"; then
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

    [ "$allow_ssh" = "true" ] || return 0

    local ssh_key_file ssh_key_content tmpscript rc
    ssh_key_file=$(find_ssh_key) || true
    if [ -z "$ssh_key_file" ] || [ ! -f "$ssh_key_file" ]; then
        message "Локальный публичный ключ (~/.ssh/*.pub)" "не найден" "$YELLOW" "$YELLOW"
        return 0
    fi

    ssh_key_content=$(cat "$ssh_key_file")
    tmpscript=$(mktemp)
    cat > "$tmpscript" <<'EOF'
_sudo mkdir -p "/home/${TARGET_USER}/.ssh"
printf '%s\n' "${SSH_PUB_KEY}" | _sudo tee -a "/home/${TARGET_USER}/.ssh/authorized_keys" >/dev/null
_sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}/.ssh"
_sudo chmod 700 "/home/${TARGET_USER}/.ssh"
_sudo chmod 600 "/home/${TARGET_USER}/.ssh/authorized_keys"
EOF

    step_name " копирование публичного ключа" "$YELLOW"
    run_ssh_bash \
        "$(printf 'export TARGET_USER=%q SSH_PUB_KEY=%q' "$name" "$ssh_key_content")" \
        "$tmpscript"
    rc=$?
    rm -f "$tmpscript"
    if [ "$rc" -eq 0 ]; then
        step_status "OK" "$GREEN"
    else
        step_status "ошибка" "$RED"
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
