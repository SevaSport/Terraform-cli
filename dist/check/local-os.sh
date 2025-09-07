#!/bin/bash

# Определяем операционную систему
OS="unknown"

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="ubuntu"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    title "Скрипт работает только в Ubuntu и MacOS" "$RED"
    exit 1
fi