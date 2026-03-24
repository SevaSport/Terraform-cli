#!/bin/bash

# Проверка ОС на машине, с которой запускается run.sh (не VPS). Требования — в spec.md.

# Определяем тип ОС и при необходимости минимальную версию (Ubuntu 20+, Windows 10+; macOS без нижней границы)
OS="unknown"

# Linux: только Ubuntu (в т.ч. WSL с Ubuntu); остальные дистрибутивы не поддерживаются сценарием
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        if [[ "${ID:-}" != "ubuntu" ]]; then
            title "На управляющем компьютере требуется Ubuntu 20+ (см. spec.md)" "$RED"
            exit 1
        fi
        OS="ubuntu"
        max_ver=$(printf '%s\n' "${VERSION_ID:-0}" "20.04" | sort -V | tail -n1)
        if [[ "$max_ver" != "${VERSION_ID:-}" ]]; then
            title "Требуется Ubuntu 20.04 или новее (см. spec.md)" "$RED"
            exit 1
        fi
    else
        title "Не удалось определить дистрибутив Linux (/etc/os-release)" "$RED"
        exit 1
    fi
# macOS: любая поддерживаемая версия (ограничения не задаём)
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
# Git Bash / Cygwin: отсекаем Windows старше 10 по строке ver (ядро 6.x без ветки 10.x)
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    OS="windows"
    if command -v cmd.exe >/dev/null 2>&1; then
        winver=$(cmd.exe //c ver 2>/dev/null | head -n1 || true)
        if [[ -n "$winver" ]] && [[ "$winver" =~ Microsoft\ Windows\ \[Version\  ]]; then
            if [[ "$winver" =~ Version\ 6\.[0-3]\. ]]; then
                title "Требуется Windows 10 или новее (см. spec.md)" "$RED"
                exit 1
            fi
        fi
    fi
else
    # Любая другая платформа (BSD и т.д.) — вне поддержки
    title "Скрипт поддерживает macOS, Windows 10+ или Ubuntu 20+ (см. spec.md)" "$RED"
    exit 1
fi
