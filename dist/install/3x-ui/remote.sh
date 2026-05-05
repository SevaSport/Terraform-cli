#!/bin/bash

# Установка 3x-ui без Docker через официальный install.sh.
set -euo pipefail

type _sudo >/dev/null 2>&1 || _sudo() { sudo "$@"; }

XUI_ACTION="${XUI_ACTION:-install}"
XUI_PANEL_PORT="${XUI_PANEL_PORT:-61197}"
XUI_SERVER_HOST="${XUI_SERVER_HOST:?XUI_SERVER_HOST is required}"
XUI_PANEL_USER="${XUI_PANEL_USER:-}"
XUI_PANEL_PASS="${XUI_PANEL_PASS:-}"
XUI_BIN="${XUI_BIN:-/usr/local/x-ui/x-ui}"
XUI_INSTALL_LOG="${XUI_INSTALL_LOG:-/var/log/3x-ui-install.log}"

get_setting_value() {
    local key="$1"
    local raw_settings=""
    raw_settings=$(_sudo "$XUI_BIN" setting -show 2>/dev/null || true)
    printf '%s\n' "$raw_settings" | awk -F': ' -v target="$key" '$1 == target {print $2; exit}'
    return 0
}

configure_panel() {
    _sudo "$XUI_BIN" setting -port "$XUI_PANEL_PORT" >/dev/null 2>&1
    if [[ -n "$XUI_PANEL_USER" && -n "$XUI_PANEL_PASS" ]]; then
        _sudo "$XUI_BIN" setting -username "$XUI_PANEL_USER" -password "$XUI_PANEL_PASS" >/dev/null 2>&1
    fi
}

print_payload() {
    local panel_user panel_pass parsed_user parsed_pass web_base_path normalized_path panel_url panel_port
    panel_user=$(get_setting_value "username")
    panel_pass="${XUI_PANEL_PASS}"
    panel_port=$(get_setting_value "port")
    [[ -z "$panel_port" ]] && panel_port="$XUI_PANEL_PORT"
    parsed_user=$(_sudo awk -F': ' '/Username:/ {u=$2} END{print u}' "$XUI_INSTALL_LOG" 2>/dev/null | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g; s/^[[:space:]]+//; s/[[:space:]]+$//' || true)
    parsed_pass=$(_sudo awk -F': ' '/Password:/ {p=$2} END{print p}' "$XUI_INSTALL_LOG" 2>/dev/null | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g; s/^[[:space:]]+//; s/[[:space:]]+$//' || true)
    web_base_path=$(get_setting_value "webBasePath")
    normalized_path="${web_base_path#/}"
    normalized_path="${normalized_path%/}"

    if [[ -n "$normalized_path" ]]; then
        panel_url="https://${XUI_SERVER_HOST}:${panel_port}/${normalized_path}/"
    else
        panel_url="https://${XUI_SERVER_HOST}:${panel_port}"
    fi
    echo "XUI_PANEL_URL=${panel_url}"
    if [[ -n "$XUI_PANEL_USER" && -n "$XUI_PANEL_PASS" ]]; then
        echo "XUI_PANEL_LOGIN=${XUI_PANEL_USER}"
        echo "XUI_PANEL_PASSWORD=${XUI_PANEL_PASS}"
    else
        if [[ -n "$parsed_user" ]]; then
            panel_user="$parsed_user"
        fi
        if [[ -n "$parsed_pass" ]]; then
            panel_pass="$parsed_pass"
        fi
        if [[ -n "$panel_user" ]]; then
            echo "XUI_PANEL_LOGIN=${panel_user}"
        fi
        if [[ -n "$panel_pass" ]]; then
            echo "XUI_PANEL_PASSWORD=${panel_pass}"
        fi
    fi
}

if [[ "$XUI_ACTION" == "payload" ]]; then
    configure_panel
    _sudo systemctl restart x-ui >/dev/null 2>&1 || true
    print_payload
    exit 0
fi

if ! _sudo bash -lc "bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) 2>&1 | tee '$XUI_INSTALL_LOG'"; then
    # install.sh may exit non-zero when Let's Encrypt hits rate limits.
    # If x-ui binary exists, continue and print parsed access data.
    if ! _sudo test -x "$XUI_BIN"; then
        exit 1
    fi
fi
configure_panel

_sudo systemctl enable x-ui >/dev/null 2>&1 || true
_sudo systemctl restart x-ui >/dev/null 2>&1 || true
print_payload
