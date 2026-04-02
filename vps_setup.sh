#!/bin/bash

# Этот скрипт нужно запускать от root на Ubuntu/Debian-based VPS
# -----------------------------------------------------------------

# ────────────────────────────────────────────────
#          Настраиваемые параметры
# ────────────────────────────────────────────────

NEW_USER="metal"  # имя создаваемого пользователя
PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtj9Yh9Qq7RISYm7TK+NHbdxhBzZS9yOV4Ew4pOPrffUA63m7c8oH7e4rIJg2/VWpjlbSsV41hoXmC3d/KyVIAWlgrWa8ePRpTaLH954rQwIHQFf86f5K9mst7i5D3acg6fTne7hMrQp79fSPKYpfDBvyLV1WUUEyLQJVCF9p6IgtPXal3gx661F4cAc6xOM7LpGalYMT3n+6J0ZRUwAYTgNxfTbk7v6r39K3c/BhD6asAe6zVP0sfwJHsPWiPh03eTMWLCSMfXe3D2HZJOVbup3q9YFvj16c5kgfThVlZIK6d5vwbMlsaVXtuuuwtte/CCZi9AQ3ewKecQqj4mThx rsa-key-20250721"

ROOT_PASS_PORT=0  # ROOT_PASS_PORT=1 отключает root-доступ, вход по паролю, меняет порт SSH на SSH_PORT
SSH_PORT=2299

# ────────────────────────────────────────────────

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                Начало первичной настройки VPS              ║"
echo "║                                                            ║"
echo "║  • Обновление системы                                      ║"
echo "║  • Установка Docker                                        ║"
echo "║  • Установка вспомогательных пакетов                       ║"
echo "║  • Создание нового пользователя                            ║"
echo "║  • Настройка sudo без пароля                               ║"
echo "║  • Добавление SSH-ключа                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Запуск от пользователя:   $(whoami)"
echo "Создаваемый пользователь: $NEW_USER"
echo "Дата/время начала:        $(date '+%Y-%m-%d %H:%M:%S')"
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

read -p "Запустить первичную настройку VPS (y/n)? " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Отменено."
    exit 0
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

# 8. Настройка SSH (условно, в зависимости от ROOT_PASS_PORT)
if [ "$ROOT_PASS_PORT" = "1" ]; then
    echo "→ 8. Настройка SSH: отключение root-доступа, входа по паролю, смена порта на $SSH_PORT"
    
    # Создаём директорию для дополнительных конфигов, если её нет
    mkdir -p /etc/ssh/sshd_config.d/
    
    # Создаём файл с настройками
    cat > /etc/ssh/sshd_config.d/01-custom-ssh-settings.conf << EOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
EOF
    
    # Проверяем, есть ли уже директива Include в основном конфиге
    if ! grep -q "^Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
        echo "→ Добавляем Include в /etc/ssh/sshd_config"
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi
    
    # Проверяем, не конфликтует ли порт с уже существующими настройками
    if grep -q "^Port " /etc/ssh/sshd_config; then
        echo "⚠ Внимание: в основном конфиге уже указан порт. Будет использован порт $SSH_PORT (из дополнительного конфига)"
    fi
    
    # Проверяем, не пытаемся ли мы использовать порт 22 (стандартный)
    if [ "$SSH_PORT" = "22" ]; then
        echo "⚠ Внимание: вы используете стандартный порт 22. Это менее безопасно."
    fi
    
    # Перезапускаем SSH сервис
    systemctl restart ssh
    
    echo "   SSH настроен: порт $SSH_PORT, root-доступ отключён, вход по паролю отключён"
else
    echo "→ 8. Пропускаем настройку SSH (ROOT_PASS_PORT = $ROOT_PASS_PORT)"
    echo "   SSH-конфигурация остаётся без изменений"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Настройка успешно завершена!              ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""