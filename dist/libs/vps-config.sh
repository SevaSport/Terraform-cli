#!/bin/bash

# Чтение config.yml (yq). До source нужна переменная CONFIGURATIONS. SSH не используется.

# Узнать, объявлен ли в config.yml раздел vps.applications для указанного приложения (есть ли ключ в YAML).
# Параметры: $1 — имя ключа (например docker, outline). Читает CONFIGURATIONS. Возврат: 0 если ключ есть, 1 если нет.
config_application_enabled() {
    [[ "$(yq eval ".vps.applications | has(\"$1\")" "$CONFIGURATIONS")" == "true" ]]
}

# Прочитать нестандартный порт SSH из vps.applications.ssh.port, если он задан в config.yml.
# Параметры: нет (читает CONFIGURATIONS). Возврат: номер порта строкой на stdout или пустая строка.
vps_ssh_application_port_optional() {
    local p
    p=$(yq e '(.vps.applications.ssh.port // "")' "$CONFIGURATIONS")
    [[ "$p" == "null" ]] && p=""
    printf '%s' "$p"
}

# Если для приложения нет секции в config, прекратить выполнение текущего подключаемого скрипта без ошибки (удобно в task.sh).
# Параметры: $1 — имя приложения. Возврат: при отсутствии секции — return 0 из source или exit 0 из скрипта.
skip_unless_application() {
    config_application_enabled "$1" || { return 0 2>/dev/null || exit 0; }
}

# Подставить в окружение логин и пароль из списка vps.users по имени пользователя (дальнейший SSH под этим пользователем).
# Параметры: $1 — искомое имя в vps.users[].name. Читает CONFIGURATIONS. Возврат: 0 — найдено и пароль непустой; 1 — нет такого пользователя; 2 — пароль пуст; побочный эффект — export VPS_USER, VPS_PASS.
export_credentials_for_vps_user_named() {
    local want="$1"
    local users_count i name pass
    users_count=$(yq eval '.vps.users | length' "$CONFIGURATIONS")
    for ((i = 0; i < users_count; i++)); do
        name=$(yq ".vps.users[$i].name" "$CONFIGURATIONS")
        if [[ "$name" == "$want" ]]; then
            pass=$(yq ".vps.users[$i].pass" "$CONFIGURATIONS")
            export VPS_USER="$name"
            export VPS_PASS="$pass"
            [[ -n "$pass" ]] || return 2
            return 0
        fi
    done
    return 1
}
