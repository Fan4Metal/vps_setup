#!/bin/bash

# Этот скрипт нужно запускать от root на Ubuntu/Debian-based VPS
# -----------------------------------------------------------------

# ────────────────────────────────────────────────
#          Настраиваемые параметры
# ────────────────────────────────────────────────

NEW_USER="metal"                          # ← измените здесь имя пользователя

PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtj9Yh9Qq7RISYm7TK+NHbdxhBzZS9yOV4Ew4pOPrffUA63m7c8oH7e4rIJg2/VWpjlbSsV41hoXmC3d/KyVIAWlgrWa8ePRpTaLH954rQwIHQFf86f5K9mst7i5D3acg6fTne7hMrQp79fSPKYpfDBvyLV1WUUEyLQJVCF9p6IgtPXal3gx661F4cAc6xOM7LpGalYMT3n+6J0ZRUwAYTgNxfTbk7v6r39K3c/BhD6asAe6zVP0sfwJHsPWiPh03eTMWLCSMfXe3D2HZJOVbup3q9YFvj16c5kgfThVlZIK6d5vwbMlsaVXtuuuwtte/CCZi9AQ3ewKecQqj4mThx rsa-key-20250721"

# ────────────────────────────────────────────────

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                Начало первичной настройки VPS              ║"
echo "║                                                            ║"
echo "║  • Обновление системы                                      ║"
echo "║  • Установка Docker                                        ║"
echo "║  • Установка вспомогательных пакетов                       ║"
echo "║  • Создание пользователя $NEW_USER                         ║"
echo "║  • Настройка sudo без пароля                               ║"
echo "║  • Добавление SSH-ключа                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Запуск от пользователя: $(whoami)"
echo "Создаваемый пользователь: $NEW_USER"
echo "Дата/время начала:     $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Проверка, что ключ выглядит примерно правильно
if [[ ! "$PUBLIC_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
    echo "Ошибка: PUBLIC_KEY не выглядит как валидный публичный SSH-ключ." >&2
    echo "Он должен начинаться с ssh-rsa, ssh-ed25519 или ssh-ecdsa..." >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Скрипт должен запускаться от root." >&2
    exit 1
fi

# 1. Обновление системы
echo "→ 1. Обновление и апгрейд пакетов без вопросов, сохраняем свои конфиги..."
DEBIAN_FRONTEND=noninteractive \
apt update && \
apt upgrade -y \
-o Dpkg::Options::="--force-confdef" \
-o Dpkg::Options::="--force-confold"

# 2. Установка Docker — только если его нет или он не запущен
echo "→ 2. Проверка и установка Docker (если требуется)..."

if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    echo "   Docker уже установлен и запущен → пропускаем установку"
else
    echo "   Docker не найден или не запущен → выполняем установку..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh
    
    # Запуск и автозапуск
    systemctl start docker
    systemctl enable docker
fi
echo "   Docker установлен и запущен"

# 3. Установка вспомогательных пакетов
echo "→ 3. Установка вспомогательных пакетов..."
apt install -y \
mc \
htop \
btop \
iftop \
bat

# 4. Создание пользователя
echo "→ 4. Создание пользователя $NEW_USER (без пароля)..."
adduser --disabled-password --gecos "" "$NEW_USER"

# 5. Добавление в группы sudo и docker
usermod -aG sudo   "$NEW_USER"
usermod -aG docker "$NEW_USER"
echo "   Пользователь $NEW_USER добавлен в группы sudo и docker"

# 6. Добавление SSH-ключа в authorized_keys
echo "→ 6. Добавление публичного SSH-ключа для $NEW_USER..."
su - "$NEW_USER" -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "$PUBLIC_KEY" | su - "$NEW_USER" -c "tee ~/.ssh/authorized_keys > /dev/null"
su - "$NEW_USER" -c "chmod 600 ~/.ssh/authorized_keys"
echo "   Ключ успешно добавлен"

# 7. sudo без пароля
echo "→ 7. Настройка sudo без пароля для $NEW_USER..."
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" | tee "/etc/sudoers.d/$NEW_USER" >/dev/null
chmod 0440 "/etc/sudoers.d/$NEW_USER"
echo "   sudo без пароля настроен"

# Опционально: отключить вход по паролю и root-доступ по ssh
# echo "→ Отключение входа root и пароля по SSH"
# sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
# sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# systemctl restart ssh

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Настройка успешно завершена!              ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "Пользователь: $NEW_USER создан"
echo ""