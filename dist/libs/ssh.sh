#!/bin/bash

# Подключение к VPS. До source должны быть заданы: VPS_IP, VPS_USER, VPS_PASS, VPS_PORT (из credentials),
# а также LOGS_DIR, DIST_DIR, CONFIGURATIONS (из run.sh). Глобально выставляется LAST_REMOTE_SCRIPT_LOG
# после run_ssh_with_file / run_ssh_bash — путь к логу последнего удалённого сценария.

# Сопоставить локальный сценарий из dist/ файлу в logs/ (имя из относительного пути, слэши → дефисы).
# Параметры: $1 — путь к .sh. Возврат: одна строка абсолютного пути .log на stdout; создаётся каталог LOGS_DIR.
remote_script_log_path() {
    local script_path="$1"
    local dir base abs dist_abs rel
    dir=$(dirname "$script_path")
    base=$(basename "$script_path")
    abs=$(cd "$dir" && pwd)/"$base"
    dist_abs=$(cd "$DIST_DIR" && pwd)
    if [[ "$abs" == "$dist_abs"/* ]]; then
        rel="${abs#"$dist_abs"/}"
    else
        rel="$base"
    fi
    rel="${rel//\//-}"
    rel="${rel%.sh}.log"
    mkdir -p "$LOGS_DIR"
    printf '%s\n' "$(cd "$LOGS_DIR" && pwd)/$rel"
}

# Список портов для перебора при подключении: сначала текущий VPS_PORT, затем из credentials и из config (ssh.port).
# Параметры: нет (читает VPS_PORT, CREDENTIALS, при наличии — vps_ssh_application_port_optional из CONFIGURATIONS).
# Возврат: по одному номеру порта на строку на stdout, без дубликатов.
ssh_port_candidates() {
    local p
    local cred_port=""
    local app_port=""
    local out=()

    if [[ -n "${CREDENTIALS:-}" && -f "${CREDENTIALS:-}" ]]; then
        cred_port=$(yq e '.vps.port' "$CREDENTIALS" 2>/dev/null || true)
    fi
    if type vps_ssh_application_port_optional >/dev/null 2>&1; then
        app_port=$(vps_ssh_application_port_optional 2>/dev/null || true)
    fi

    for p in "${VPS_PORT:-}" "$cred_port" "$app_port"; do
        [[ -n "$p" && "$p" != "null" ]] || continue
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        if [[ " ${out[*]} " != *" $p "* ]]; then
            out+=("$p")
        fi
    done

    printf '%s\n' "${out[@]}"
}

# Запомнить порт, через который удалось установить SSH-сессию, чтобы дальше использовать тот же порт.
# Параметры: $1 — номер порта (пусто — ничего не делает). Возврат: 0; побочный эффект — export VPS_PORT.
_set_active_vps_port() {
    local p="$1"
    [[ -n "$p" ]] || return 0
    export VPS_PORT="$p"
}

# Таймаут TCP для ssh (секунды) из client.ssh-connect-timeout в config.yml, при отсутствии — 5.
# Параметры: нет (читает CONFIGURATIONS). Возврат: одна строка с числом на stdout.
ssh_connect_timeout() {
    local t
    t=$(yq e '(.client."ssh-connect-timeout" // 5)' "$CONFIGURATIONS" 2>/dev/null || true)
    [[ -n "$t" && "$t" != "null" && "$t" =~ ^[0-9]+$ ]] || t=5
    printf '%s\n' "$t"
}

# Сколько раз повторять попытку SSH после сбоя — из client.ssh-reconnect-attempts, при отсутствии — 10.
# Параметры: нет (читает CONFIGURATIONS). Возврат: одна строка с числом на stdout.
ssh_reconnect_attempts() {
    local n
    n=$(yq e '(.client."ssh-reconnect-attempts" // 10)' "$CONFIGURATIONS" 2>/dev/null || true)
    [[ -n "$n" && "$n" != "null" && "$n" =~ ^[0-9]+$ ]] || n=10
    printf '%s\n' "$n"
}

# Показать пользователю путь к логу последнего удалённого сценария (если переменная уже выставлена).
# Параметры: нет (читает LAST_REMOTE_SCRIPT_LOG). Возврат: 0; вывод — через print_log_file_paths (нужен shell-messages.sh).
print_last_remote_script_log_path() {
    [[ -n "${LAST_REMOTE_SCRIPT_LOG:-}" ]] || return 0
    print_log_file_paths "$LAST_REMOTE_SCRIPT_LOG"
}

# Сгенерировать преамбулу для удалённого bash -s: при логине не root — передача пароля в sudo через SUDO_PASS и функции _sudo / _sudo_tee_file.
# Параметры: нет (читает VPS_USER, VPS_PASS). Возврат: текст на stdout для конкатенации в начало stdin ssh.
_remote_stream_sudo_header() {
    if [[ "${VPS_USER:-root}" != "root" && -n "${VPS_PASS:-}" ]]; then
        printf 'export SUDO_PASS=%s\n' "$(printf '%q' "$VPS_PASS")"
    fi
    cat <<'EOSUDO'

_sudo() {
    if [[ -n "${SUDO_PASS:-}" ]]; then
        printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"
    else
        sudo "$@"
    fi
}
_sudo_tee_file() {
    local _dest="$1"
    if [[ -n "${SUDO_PASS:-}" ]]; then
        {
            printf '%s\n' "$SUDO_PASS"
            cat
        } | sudo -S -p '' tee "$_dest" >/dev/null
    else
        sudo tee "$_dest" >/dev/null
    fi
}
EOSUDO
}

# Выполнить одну команду в удалённом shell; при сбое соединения (код 255) перебирает кандидатов портов.
# Параметры: $1 — строка команды для удалённого shell. Читает VPS_USER, VPS_IP. Возврат: код завершения ssh.
run_ssh() {
    local command="$1"
    local port rc=255
    local timeout
    timeout=$(ssh_connect_timeout)
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        ssh -o ConnectTimeout="$timeout" -p "$port" "$VPS_USER@$VPS_IP" "$command"
        rc=$?
        if [[ "$rc" -eq 255 ]]; then
            continue
        fi
        _set_active_vps_port "$port"
        return "$rc"
    done < <(ssh_port_candidates)
    return "$rc"
}

# Запустить локальный сценарий на VPS через stdin bash -s; весь вывод дописывается в файл лога, в консоль не идёт.
# Параметры: $1 — путь к .sh. Возврат: код ssh; побочный эффект — export LAST_REMOTE_SCRIPT_LOG на путь лога.
run_ssh_with_file() {
    local file="$1"
    local log rc=255 port
    local timeout
    timeout=$(ssh_connect_timeout)
    log=$(remote_script_log_path "$file")
    export LAST_REMOTE_SCRIPT_LOG="$log"
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        {
            printf '========== %s  %s (port %s) ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "$file" "$port"
            {
                _remote_stream_sudo_header
                cat "$file"
            } | ssh -o ConnectTimeout="$timeout" -p "$port" "$VPS_USER@$VPS_IP" "bash -s" 2>&1
            rc=${PIPESTATUS[1]}
        } >>"$log" 2>&1
        if [[ "$rc" -eq 255 ]]; then
            continue
        fi
        _set_active_vps_port "$port"
        return "$rc"
    done < <(ssh_port_candidates)
    return "$rc"
}

# Передать на VPS сценарий через stdin bash -s, предварительно выставив на удалённой стороне переменные окружения отдельными строками export (обходит запуск одной строки через dash на стороне ssh).
# Параметры: $1 — одна или несколько строк export для удалённого процесса; $2 — путь к .sh. Возврат: код ssh; LAST_REMOTE_SCRIPT_LOG обновляется.
run_ssh_bash() {
    local env_prefix="$1"
    local script_file="$2"
    local log rc=255 port
    local timeout
    timeout=$(ssh_connect_timeout)
    log=$(remote_script_log_path "$script_file")
    export LAST_REMOTE_SCRIPT_LOG="$log"
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        {
            printf '========== %s  %s (port %s) ==========\n' "$(date "+%Y-%m-%d %H:%M:%S")" "$script_file" "$port"
            {
                _remote_stream_sudo_header
                [[ -n "$env_prefix" ]] && printf '%s\n' "$env_prefix"
                cat "$script_file"
            } | ssh -o ConnectTimeout="$timeout" -p "$port" "$VPS_USER@$VPS_IP" "bash -s" 2>&1
            rc=${PIPESTATUS[1]}
        } >>"$log" 2>&1
        if [[ "$rc" -eq 255 ]]; then
            continue
        fi
        _set_active_vps_port "$port"
        return "$rc"
    done < <(ssh_port_candidates)
    return "$rc"
}

# Проверить по выводу dpkg -l на VPS, встречается ли подстрока в имени пакета.
# Параметры: $1 — фрагмент имени (подставляется в grep на удалённой машине). Возврат: 0 если найдено, иначе не 0.
is_package_installed() {
    local package="$1"
    run_ssh "dpkg -l | grep '$package' > /dev/null 2>&1"
}

# Установить один deb-пакет на VPS через apt install -y, подавив вывод apt.
# Параметры: $1 — имя пакета. Возврат: код завершения удалённой команды.
apt_install_package_remote() {
    run_ssh "sudo apt install -y '$1' > /dev/null 2>&1"
}

# Запустить удалённый сценарий из файла и показать пару message при успехе или при ошибке; при ошибке — путь к логу и завершение процесса.
# Параметры: $1 — путь к .sh; $2, $3 — левая и правая части message при успехе; $4, $5 — при ошибке. Возврат: не возвращается при ошибке (exit 1).
run_ssh_with_file_or_message_exit() {
    local script_path="$1"
    local ok_l="$2" ok_r="$3"
    local err_l="$4" err_r="$5"
    if run_ssh_with_file "$script_path"; then
        message "$ok_l" "$ok_r" "$YELLOW" "$GREEN"
    else
        message "$err_l" "$err_r" "$YELLOW" "$RED"
        print_last_remote_script_log_path
        exit 1
    fi
}

# Проверить, что на VPS пускает только по ключу (BatchMode, без интерактива).
# Параметры: нет (читает VPS_USER, VPS_IP; таймаут из ssh_connect_timeout). Возврат: 0 при успешном exit на сервере, 1 иначе.
ssh_key_batch_login_ok() {
    local port
    local timeout
    timeout=$(ssh_connect_timeout)
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        if ssh -q -o ConnectTimeout="$timeout" -o BatchMode=yes -p "$port" "$VPS_USER@$VPS_IP" exit; then
            _set_active_vps_port "$port"
            return 0
        fi
    done < <(ssh_port_candidates)
    return 1
}

# После смены порта sshd периодически проверять вход по ключу, пока сервер не ответит или не исчерпаются попытки.
# Параметры: нет (число попыток — ssh_reconnect_attempts; пауза между попытками — REBOOT_WAIT_TIME, по умолчанию 5 с). Возврат: 0 при успехе, 1 при исчерпании попыток; пишет message в консоль.
wait_for_ssh_after_sshd_port_change() {
    local max_attempts
    max_attempts=$(ssh_reconnect_attempts)
    local sleep_sec="${REBOOT_WAIT_TIME:-5}"
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if ssh_key_batch_login_ok 2>/dev/null; then
            message "Переподключение по новому SSH-порту" "Выполнено" "$YELLOW" "$GREEN"
            return 0
        fi
        message "Повтор подключения SSH ($attempt/$max_attempts)" "нет ответа" "$YELLOW" "$CYAN"
        sleep "$sleep_sec"
        attempt=$((attempt + 1))
    done
    message "Переподключение по новому SSH-порту" "Ошибка" "$YELLOW" "$RED"
    return 1
}

# Выполнить удалённый сценарий из файла и оформить результат одной строкой step_name + step_status (без exit процесса).
# Параметры: $1 — путь к .sh; $2 — подпись левой части шага. Возврат: тот же код, что у run_ssh_with_file; при ошибке печатается путь лога.
run_ssh_with_file_step_result() {
    local script_path="$1"
    local step_label="$2"
    run_ssh_with_file "$script_path"
    local result=$?
    step_name "$step_label" "$YELLOW"
    if [ $result -eq 0 ]; then
        step_status "ОК" "$GREEN"
    else
        step_status "ошибка (код: $result)" "$RED"
        print_last_remote_script_log_path
    fi
    return $result
}

# Получить с VPS краткую числовую версию Docker (первая группа цифр и точек из docker --version).
# Параметры: нет. Возврат: строка на stdout (может быть пустой при ошибке ssh/команды).
remote_docker_engine_version() {
    run_ssh "docker --version 2>/dev/null" | sed -E 's/[^0-9.]+([0-9.]+).*/\1/'
}

# Получить с VPS краткую версию плагина docker compose v2 из вывода «docker compose version».
# Параметры: нет. Возврат: строка на stdout (может быть пустой).
remote_docker_compose_v2_version() {
    run_ssh "docker compose version 2>/dev/null" | sed -E 's/[^0-9.]+([0-9.]+).*/\1/'
}
