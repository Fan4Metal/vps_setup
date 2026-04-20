#!/bin/bash

# Этот скрипт нужно запускать от root на Ubuntu/Debian-based VPS
# -----------------------------------------------------------------

# ────────────────────────────────────────────────
#          Настраиваемые параметры
# ────────────────────────────────────────────────

NEW_USER="metal"  # имя создаваемого пользователя
PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtj9Yh9Qq7RISYm7TK+NHbdxhBzZS9yOV4Ew4pOPrffUA63m7c8oH7e4rIJg2/VWpjlbSsV41hoXmC3d/KyVIAWlgrWa8ePRpTaLH954rQwIHQFf86f5K9mst7i5D3acg6fTne7hMrQp79fSPKYpfDBvyLV1WUUEyLQJVCF9p6IgtPXal3gx661F4cAc6xOM7LpGalYMT3n+6J0ZRUwAYTgNxfTbk7v6r39K3c/BhD6asAe6zVP0sfwJHsPWiPh03eTMWLCSMfXe3D2HZJOVbup3q9YFvj16c5kgfThVlZIK6d5vwbMlsaVXtuuuwtte/CCZi9AQ3ewKecQqj4mThx rsa-key-20250721"

HARDEN_SSH="${HARDEN_SSH:-}"  # HARDEN_SSH=1 отключает root-доступ, вход по паролю, меняет порт SSH на SSH_PORT
SSH_PORT="${SSH_PORT:-2299}"

# Цвета вывода
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD='\033[1m'
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    BLUE='\033[34m'
    CYAN='\033[36m'
    RESET='\033[0m'
else
    BOLD=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    RESET=''
fi

info() {
    printf "%b\n" "${CYAN}→ $*${RESET}"
}

success() {
    printf "%b\n" "${GREEN}✓ $*${RESET}"
}

warn() {
    printf "%b\n" "${YELLOW}⚠ $*${RESET}"
}

error() {
    printf "%b\n" "${RED}Ошибка: $*${RESET}" >&2
}

# ────────────────────────────────────────────────

ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local answer
    
    while true; do
        read -r -p "$prompt " answer
        
        if [ -z "$answer" ]; then
            answer="$default"
        fi
        
        case "$answer" in
            y|Y|yes|YES|д|Д|да|ДА) return 0 ;;
            n|N|no|NO|н|Н|нет|НЕТ) return 1 ;;
            *) warn "Введите y или n." ;;
        esac
    done
}

# Проверка, что ключ выглядит примерно правильно
if [[ ! "$PUBLIC_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
    error "PUBLIC_KEY не выглядит как валидный публичный SSH-ключ."
    error "Он должен начинаться с ssh-rsa, ssh-ed25519 или ssh-ecdsa..."
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт должен запускаться от root."
    exit 1
fi

if [ -z "$HARDEN_SSH" ]; then
    if ask_yes_no "Усилить SSH: отключить root, отключить парольный вход и сменить порт на $SSH_PORT? [y/N]" "n"; then
        HARDEN_SSH=1
    else
        HARDEN_SSH=0
    fi
    elif [[ "$HARDEN_SSH" != "0" && "$HARDEN_SSH" != "1" ]]; then
    error "HARDEN_SSH должен быть 0 или 1."
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                Начало первичной настройки VPS              ║"
echo "║                                                            ║"
echo "║  • Обновление системы                                      ║"
echo "║  • Установка Docker                                        ║"
echo "║  • Установка вспомогательных пакетов                       ║"
echo "║  • Создание нового пользователя                            ║"
echo "║  • Настройка sudo без пароля                               ║"
echo "║  • Добавление SSH-ключа                                    ║"
if [ "$HARDEN_SSH" = "1" ]; then
    echo "║  • Отключение root-доступа                                 ║"
    echo "║  • Отключение входа по паролю                              ║"
    echo "║  • Смена порта SSH                                         ║"
fi
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Запуск от пользователя:   $(whoami)"
echo "Создаваемый пользователь: $NEW_USER"
if [ "$HARDEN_SSH" = "1" ]; then
    echo "Порт SSH:                 $SSH_PORT"
fi
echo "Дата/время начала:        $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

read -r -p "Запустить первичную настройку VPS (y/n)? " confirm
if [[ "$confirm" != "y" ]]; then
    warn "Отменено."
    exit 0
fi

# 1. Обновление системы
info "1. Обновление и апгрейд пакетов без вопросов, сохраняем свои конфиги..."
DEBIAN_FRONTEND=noninteractive \
apt update && \
apt upgrade -y \
-o Dpkg::Options::="--force-confdef" \
-o Dpkg::Options::="--force-confold"

# 2. Установка Docker — только если его нет или он не запущен
info "2. Проверка и установка Docker (если требуется)..."

if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    success "Docker уже установлен и запущен → пропускаем установку"
else
    info "Docker не найден или не запущен → выполняем установку..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh
    
    # Запуск и автозапуск
    systemctl start docker
    systemctl enable docker
fi
success "Docker установлен и запущен"

# 3. Установка вспомогательных пакетов
info "3. Установка вспомогательных пакетов..."
apt install -y \
mc \
htop \
btop \
iftop \
bat \
micro

# 4. Создание пользователя
info "4. Создание пользователя $NEW_USER (без пароля)..."
adduser --disabled-password --gecos "" "$NEW_USER"

# 5. Добавление в группы sudo и docker
usermod -aG sudo   "$NEW_USER"
usermod -aG docker "$NEW_USER"
success "Пользователь $NEW_USER добавлен в группы sudo и docker"

# 6. Добавление SSH-ключа в authorized_keys
info "6. Добавление публичного SSH-ключа для $NEW_USER..."
su - "$NEW_USER" -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "$PUBLIC_KEY" | su - "$NEW_USER" -c "tee ~/.ssh/authorized_keys > /dev/null"
su - "$NEW_USER" -c "chmod 600 ~/.ssh/authorized_keys"
success "Ключ успешно добавлен"

# 7. sudo без пароля
info "7. Настройка sudo без пароля для $NEW_USER..."
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" | tee "/etc/sudoers.d/$NEW_USER" >/dev/null
chmod 0440 "/etc/sudoers.d/$NEW_USER"
success "sudo без пароля настроен"

# 8. Настройка SSH (условно, в зависимости от HARDEN_SSH)
if [ "$HARDEN_SSH" = "1" ]; then
    info "8. Настройка SSH: отключение root-доступа, входа по паролю, смена порта на $SSH_PORT"
    
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
        info "Добавляем Include в /etc/ssh/sshd_config"
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi
    
    # Проверяем, не конфликтует ли порт с уже существующими настройками
    if grep -q "^Port " /etc/ssh/sshd_config; then
        warn "В основном конфиге уже указан порт. Будет использован порт $SSH_PORT (из дополнительного конфига)"
    fi
    
    # Проверяем, не пытаемся ли мы использовать порт 22 (стандартный)
    if [ "$SSH_PORT" = "22" ]; then
        warn "Вы используете стандартный порт 22. Это менее безопасно."
    fi
    
    # Перезапускаем SSH сервис
    systemctl restart ssh
    
    success "SSH настроен: порт $SSH_PORT, root-доступ отключён, вход по паролю отключён"
else
    info "8. Пропускаем настройку SSH (HARDEN_SSH = $HARDEN_SSH)"
    success "SSH-конфигурация остаётся без изменений"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Настройка успешно завершена!              ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
