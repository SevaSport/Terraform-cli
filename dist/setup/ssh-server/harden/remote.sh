#!/bin/bash
# Выполняется на VPS: drop-in конфиг для sshd (запрет root и пароля), проверка конфигурации и перезапуск службы ssh.
set -euo pipefail

_sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

_sudo sshd -t
_sudo systemctl restart ssh
