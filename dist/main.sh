#!/bin/bash

# Сценарий после run.sh: сначала убеждаемся, что с вашего компьютера можно безопасно
# управлять VPS, затем по очереди применяем настройки из config.yml / credentials.yml.

#----------
# У вас подходящая ОС и установлены yq и sshpass (без них скрипт не запустится).
source "$CHECK_SCRIPTS/local-os.sh"

# При необходимости доустановит недостающие утилиты (Homebrew или apt).
source "$CHECK_SCRIPTS/local-packages.sh"

# Поддержка credentials.yml в двух форматах:
# 1) Один VPS (обратная совместимость):
#    vps: { ip, port, user, pass }
# 2) Массив VPS:
#    vps:
#      - { ip, port, user, pass }
#      - { ip, port, user, pass }
collect_vps_targets() {
    local vps_type vps_count i
    VPS_TARGETS_IP=()
    VPS_TARGETS_PORT=()
    VPS_TARGETS_USER=()
    VPS_TARGETS_PASS=()

    vps_type=$(yq e '.vps | type' "$CREDENTIALS" 2>/dev/null || true)

    if [[ "$vps_type" == "!!seq" ]]; then
        vps_count=$(yq e '.vps | length' "$CREDENTIALS" 2>/dev/null || echo 0)
        [[ "$vps_count" =~ ^[0-9]+$ ]] || vps_count=0
        for ((i = 0; i < vps_count; i++)); do
            VPS_TARGETS_IP+=("$(yq e ".vps[$i].ip // \"\"" "$CREDENTIALS" 2>/dev/null || true)")
            VPS_TARGETS_PORT+=("$(yq e ".vps[$i].port // \"\"" "$CREDENTIALS" 2>/dev/null || true)")
            VPS_TARGETS_USER+=("$(yq e ".vps[$i].user // \"\"" "$CREDENTIALS" 2>/dev/null || true)")
            VPS_TARGETS_PASS+=("$(yq e ".vps[$i].pass // \"\"" "$CREDENTIALS" 2>/dev/null || true)")
        done
    else
        VPS_TARGETS_IP+=("$(yq e '.vps.ip // ""' "$CREDENTIALS" 2>/dev/null || true)")
        VPS_TARGETS_PORT+=("$(yq e '.vps.port // ""' "$CREDENTIALS" 2>/dev/null || true)")
        VPS_TARGETS_USER+=("$(yq e '.vps.user // ""' "$CREDENTIALS" 2>/dev/null || true)")
        VPS_TARGETS_PASS+=("$(yq e '.vps.pass // ""' "$CREDENTIALS" 2>/dev/null || true)")
    fi
}

run_for_current_vps() {
    #----------
    # Если IP/порт/логин/пароль не заданы — скрипт спросит их в терминале.
    source "$VALIDATE_SCRIPTS/ssh-config.sh"

    #----------
    # Проверка ssh и ключей; при отсутствии ключа — предложение создать.
    source "$CHECK_SCRIPTS/local-ssh-key.sh"

    #----------
    # Копирование ключа на сервер и проверка входа без пароля (дальше работа идёт по ключу).
    source "$CHECK_SCRIPTS/ssh-connection.sh"

    #----------
    # Дальше — изменения на самом сервере; порядок важен (сеть → SSH → фаервол → сервисы).
    title "Выполнение команд на удалённом сервере" "$BLUE"

    # Отключение IPv6 на сервере — только если задано в config.yml (иначе шаг пропускается внутри модуля).
    source "$SETUP_SCRIPTS/ipv6-switch/task.sh"
    # Обновление системы на VPS; при необходимости перезагрузка и ожидание.
    source "$INSTALL_SCRIPTS/update/task.sh"

    #----------
    # Установка списка пакетов из config.yml (nano, ufw и т.д.).
    source "$INSTALL_SCRIPTS/packages/task.sh"

    #----------
    # Проверка информации о VPS (Ubuntu 20+): ОС, CPU, ОЗУ, диск и короткие тесты (см. remote-os.sh).
    # Шаг идёт после установки пакетов, т.к. для части тестов нужен sysbench/curl из vps.packages.
    source "$CHECK_SCRIPTS/remote-os.sh"

    #----------
    # Создание пользователей, sudo, ключи в authorized_keys — как в config.yml.
    source "$SETUP_SCRIPTS/users/task.sh"

    # Настройки безопасности sshd, смена порта SSH при необходимости, фаервол и fail2ban.
    source "$SETUP_SCRIPTS/ssh-server/harden/task.sh"
    source "$SETUP_SCRIPTS/ssh-server/port/task.sh"
    source "$SETUP_SCRIPTS/ufw/task.sh"
    source "$SETUP_SCRIPTS/fail2ban/task.sh"

    # Установка Docker, если задано в applications.docker
    source "$INSTALL_SCRIPTS/docker/task.sh"

    # # VPN Outline
    # source "$INSTALL_SCRIPTS/outline/task.sh"

    # # 3x-ui (панель управления VPN)
    # source "$INSTALL_SCRIPTS/3x-ui/task.sh"

    # # AmneziaWG VPN (Docker)
    # source "$INSTALL_SCRIPTS/amneziawg/task.sh"
}

collect_vps_targets
VPS_TARGETS_TOTAL=${#VPS_TARGETS_IP[@]}

for ((VPS_TARGET_IDX = 0; VPS_TARGET_IDX < VPS_TARGETS_TOTAL; VPS_TARGET_IDX++)); do
    VPS_IP="${VPS_TARGETS_IP[$VPS_TARGET_IDX]}"
    VPS_PORT="${VPS_TARGETS_PORT[$VPS_TARGET_IDX]}"
    VPS_USER="${VPS_TARGETS_USER[$VPS_TARGET_IDX]}"
    VPS_PASS="${VPS_TARGETS_PASS[$VPS_TARGET_IDX]}"

    [[ "$VPS_IP" == "null" ]] && VPS_IP=""
    [[ "$VPS_PORT" == "null" ]] && VPS_PORT=""
    [[ "$VPS_USER" == "null" ]] && VPS_USER=""
    [[ "$VPS_PASS" == "null" ]] && VPS_PASS=""

    if (( VPS_TARGETS_TOTAL > 1 )); then
        title "Обработка VPS $((VPS_TARGET_IDX + 1))/$VPS_TARGETS_TOTAL" "$BLUE"
    fi

    run_for_current_vps
done

exit 0
