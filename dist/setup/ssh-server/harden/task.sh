#!/bin/bash

# На сервере создаётся drop-in для sshd: запрет входа root и входа по
# паролю (остаётся только ключ). Сразу после этого сценарий переключает
# переменные VPS_USER/VPS_PASS на пользователя «ssh» из vps.users —
# иначе дальнейшие SSH-команды от прежнего root не пройдут.

setup_ssh_hardening() {
    local cred_rc

    skip_unless_application ssh
    title "Настройки безопасности SSH" "$BLUE"

    run_ssh_with_file_or_message_exit "$SETUP_SCRIPTS/ssh-server/harden/remote.sh" \
        "Запрет входа root и пароля по SSH" "OK" \
        "Запрет входа root и пароля по SSH" "Ошибка"

    export_credentials_for_vps_user_named ssh
    cred_rc=$?
    if [ "$cred_rc" -eq 1 ]; then
        message "Пользователь ssh в vps.users" "не найден" "$RED" "$RED"
        exit 1
    elif [ "$cred_rc" -eq 2 ]; then
        message "Пароль пользователя ssh в config" "не задан" "$RED" "$RED"
        exit 1
    fi

    if ssh_key_batch_login_ok; then
        message "Вход по SSH-ключу (пользователь $VPS_USER)" "Выполнен" "$YELLOW" "$GREEN"
    else
        message "Вход по SSH-ключу (пользователь $VPS_USER)" "Ошибка" "$YELLOW" "$RED"
        exit 1
    fi
}

setup_ssh_hardening
