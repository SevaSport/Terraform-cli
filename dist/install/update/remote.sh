#!/bin/bash

# Обновление библиотек
sudo apt update > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1 && sudo apt autoremove -y > /dev/null 2>&1
exit $?