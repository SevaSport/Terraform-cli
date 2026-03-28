#!/bin/bash

# Первый заход: проверка SSH по паролю с выбором порта, затем ssh-copy-id
# и проверка входа по ключу без пароля (BatchMode).

title "Проверка и настройка SSH-подключения к VPS" "$BLUE"

SSH_CONNECTION_LOG="$LOGS_DIR/ssh-connection.log"
printf '========== %s  %s ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "ssh-connection" >"$SSH_CONNECTION_LOG"
SSH_CONNECT_TIMEOUT=$(ssh_connect_timeout)

# Запускает переданную команду и пишет оба потока в общий лог шага.
# Вход:
#   $@ - команда и её аргументы для выполнения.
run_logged() {
    "$@" >>"$SSH_CONNECTION_LOG" 2>&1
}

# Анализ текста ошибки SSH: изменился ключ хоста в known_hosts.
is_host_key_changed_error() {
    local out="${1:-}"
    [[ "$out" == *"REMOTE HOST IDENTIFICATION HAS CHANGED"* ]] && return 0
    [[ "$out" == *"Host key verification failed"* ]] && return 0
    [[ "$out" == *"Offending "* && "$out" == *"known_hosts"* ]] && return 0
    return 1
}

# Копирование публичного SSH-ключа на сервер с fallback-попыткой.
copy_ssh_key_to_server() {
    step_name "Копирование публичного SSH-ключа на сервер" "$YELLOW"
    printf '========== %s  %s ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "ssh-copy-id" >>"$SSH_CONNECTION_LOG"
    run_logged sshpass -p "$VPS_PASS" ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o NumberOfPasswordPrompts=1 -p "$VPS_PORT" "$VPS_USER@$VPS_IP"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        run_logged sshpass -p "$VPS_PASS" ssh-copy-id -p "$VPS_PORT" "$VPS_USER@$VPS_IP"
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        step_status "OK" "$GREEN"
    else
        step_status "ошибка" "$RED"
    fi
    return "$rc"
}

# Если known_hosts уже содержит VPS_IP: сначала пробуем подключения "как есть" (с проверкой host key),
# и только если все способы провалены — чистим known_hosts.
# Выполняет «мягкую» проверку существующей host key:
# для каждого порта пытается вход по паролю и по ключу без изменения known_hosts.
try_ssh() {
    local credentials_port
    local app_port
    local ports=()
    local users=("$VPS_USER:$VPS_PASS")
    local users_count
    local i
    local cfg_user
    local cfg_pass
    local port
    local entry
    local user
    local pass
    local out
    local rc=1
    
    credentials_port=$(yq e '.vps.port' "$CREDENTIALS")
    # Массив портов для проверки
    app_port=$(vps_ssh_application_port_optional)
    [[ -n "$credentials_port" && "$credentials_port" != "null" && "$credentials_port" =~ ^[0-9]+$ ]] && ports+=("$credentials_port")
    [[ -n "$app_port" && "$app_port" != "null" && "$app_port" =~ ^[0-9]+$ && "$app_port" != "$credentials_port" ]] && ports+=("$app_port")

    # Массив users формата "user:password" из config.yml -> vps.users[].
    # Добавляем только пользователей, которым разрешен SSH (allow_ssh: true).
    users_count=$(yq e '.vps.users | length' "$CONFIGURATIONS" 2>/dev/null || echo 0)
    for ((i = 0; i < users_count; i++)); do
        local cfg_allow_ssh
        cfg_user=$(yq e ".vps.users[$i].name" "$CONFIGURATIONS")
        cfg_pass=$(yq e ".vps.users[$i].pass" "$CONFIGURATIONS")
        cfg_allow_ssh=$(yq e ".vps.users[$i].allow_ssh" "$CONFIGURATIONS")
        [[ -n "$cfg_user" && "$cfg_user" != "null" ]] || continue
        [[ -n "$cfg_pass" && "$cfg_pass" != "null" ]] || continue
        [[ "$cfg_allow_ssh" == "true" ]] || continue
        users+=("$cfg_user:$cfg_pass")
    done

    # Вход:
    #   $1 - port: номер порта SSH.
    #   $2 - user: имя пользователя SSH.
    #   $3 - pass: пароль пользователя SSH.
    try_connect_using_password() {
        local port="$1"
        local user="$2"
        local pass="$3"

        step_name "Поключение к SSH: порт $port + пароль ($user)" "$YELLOW"
        out=$(
            sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o NumberOfPasswordPrompts=1 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o KbdInteractiveAuthentication=no -p "$port" "$user@$VPS_IP" "exit" \
                2>&1
        )
        rc=$?
        printf '%s\n' "$out" >>"$SSH_CONNECTION_LOG"
        if is_host_key_changed_error "$out"; then
            step_status "host key changed" "$RED"
            # Очистка known_hosts
            clear_known_hosts_for_vps
            # повторная попытка подключения
            step_name "Повтор: порт $port + пароль ($user)" "$YELLOW"
            out=$(
                sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o NumberOfPasswordPrompts=1 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o KbdInteractiveAuthentication=no -p "$port" "$user@$VPS_IP" "exit" \
                    2>&1
            )
            rc=$?
        fi
        if [ "$rc" -eq 0 ]; then
            step_status "OK" "$GREEN"
            export VPS_PORT="$port"
            export VPS_USER="$user"
            export VPS_PASS="$pass"
            if copy_ssh_key_to_server; then
                return 0
            fi
            return 1
        fi
        step_status "ошибка" "$RED"
        return "$rc"
    }

    # Вход:
    #   $1 - port: номер порта SSH.
    #   $2 - user: имя пользователя SSH.
    #   $3 - pass: пароль пользователя SSH (для дальнейших sudo-операций).
    try_connect_using_key() {
        local port="$1"
        local user="$2"
        local pass="$3"
        
        step_name "Поключение к SSH: порт $port + ключ ($user)" "$YELLOW"
        out=$(
            ssh -q -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o NumberOfPasswordPrompts=1 -o PreferredAuthentications=publickey -o PasswordAuthentication=no -p "$port" "$user@$VPS_IP" "exit" \
                2>&1
        )
        rc=$?
        printf '%s\n' "$out" >>"$SSH_CONNECTION_LOG"
        if is_host_key_changed_error "$out"; then
            # Очистка known_hosts
            clear_known_hosts_for_vps
            # повторная попытка подключения
            step_name "Повтор: порт $port + ключ ($user)" "$YELLOW"
            out=$(
                ssh -q -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o NumberOfPasswordPrompts=1 -o PreferredAuthentications=publickey -o PasswordAuthentication=no -p "$port" "$user@$VPS_IP" "exit" \
                    2>&1
            )
            rc=$?
        fi
        if [ "$rc" -eq 0 ]; then
            step_status "OK" "$GREEN"
            export VPS_PORT="$port"
            export VPS_USER="$user"
            export VPS_PASS="$pass"
            if copy_ssh_key_to_server; then
                return 0
            fi
            return 1
        fi
        step_status "ошибка" "$RED"
        return "$rc"
    }

    for port in "${ports[@]}"; do
        [[ -n "$port" && "$port" != "null" ]] || return 1
        [[ "$port" =~ ^[0-9]+$ ]] || return 1

        for entry in "${users[@]}"; do
            user="${entry%%:*}"
            pass="${entry#*:}"
            if try_connect_using_password "$port" "$user" "$pass" || try_connect_using_key "$port" "$user" "$pass"; then
                return 0
            fi
        done
    done

    if [[ "${#ports[@]}" -eq 0 ]]; then
        rc=1
    fi
    
    return "$rc"
}

# Если IP сервера найдена в known_hosts, пробуем подключиться, иначе копируем ключ на сервер
if [ "${KNOWN_HOSTS_FOUND:-0}" = "1" ]; then
    # Пробуем подключиться к SSH-серверу, если не удалось, очищаем known_hosts
    try_ssh
    try_ssh_rc=$?
    if [ "$try_ssh_rc" -ne 0 ]; then
        message "Удаленный сервер недоступен" "" "$RED" "$RED"
        print_log_file_paths "$SSH_CONNECTION_LOG"
        exit 1
    fi
else
    # step_name "Проверка подключения по SSH" "$YELLOW"
    # printf '========== %s  %s ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "ssh-copy-id $VPS_PASS $VPS_USER@$VPS_IP:$VPS_PORT" >>"$SSH_CONNECTION_LOG"
    # run_logged sshpass -p "$VPS_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o BatchMode=yes -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "exit"
    # if [ $? -eq 0 ]; then
    #     step_status "OK" "$GREEN"
    # else
    #     step_status "Ошибка" "$RED"
    #     clear_known_hosts_for_vps "silent"
    #     message "Сервер ($VPS_USER@$VPS_IP:$VPS_PORT)" "Недоступен" "$RED" "$RED"
    #     print_log_file_paths "$SSH_CONNECTION_LOG"
    #     exit 1
    # fi

    copy_ssh_key_to_server
fi

# Проверка: вход без пароля, только ключ (BatchMode=yes); вывод ssh — только в логи, не в консоль.
step_name "Проверка входа по SSH-ключу" "$YELLOW"
printf '========== %s  %s ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "ssh-batch" >>"$SSH_CONNECTION_LOG"
{
    printf '========== %s  ssh BatchMode (без пароля) ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")"
    ssh_key_batch_login_ok
    verify_rc=$?
} >>"$SSH_CONNECTION_LOG" 2>&1

if [ "$verify_rc" -eq 0 ]; then
    step_status "OK" "$GREEN"
else
    step_status "Ошибка" "$RED"
    print_log_file_paths "$SSH_CONNECTION_LOG"
    exit 1
fi