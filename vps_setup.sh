#!/bin/bash

# Этот скрипт нужно запускать от root на Ubuntu/Debian-based VPS
# -----------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ────────────────────────────────────────────────
#          Настраиваемые параметры
# ────────────────────────────────────────────────

DEFAULT_NEW_USER="metal"  # имя создаваемого пользователя по умолчанию
# Публичные SSH-ключи по умолчанию (можно перечислить несколько — по одному на строку)
DEFAULT_PUBLIC_KEYS=(
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtj9Yh9Qq7RISYm7TK+NHbdxhBzZS9yOV4Ew4pOPrffUA63m7c8oH7e4rIJg2/VWpjlbSsV41hoXmC3d/KyVIAWlgrWa8ePRpTaLH954rQwIHQFf86f5K9mst7i5D3acg6fTne7hMrQp79fSPKYpfDBvyLV1WUUEyLQJVCF9p6IgtPXal3gx661F4cAc6xOM7LpGalYMT3n+6J0ZRUwAYTgNxfTbk7v6r39K3c/BhD6asAe6zVP0sfwJHsPWiPh03eTMWLCSMfXe3D2HZJOVbup3q9YFvj16c5kgfThVlZIK6d5vwbMlsaVXtuuuwtte/CCZi9AQ3ewKecQqj4mThx rsa-key-20250721"
)

HARDEN_SSH="${HARDEN_SSH:-}"  # HARDEN_SSH=1 отключает root-доступ, вход по паролю, меняет порт SSH на SSH_PORT
SSH_PORT="${SSH_PORT:-2299}"

LOG_FILE="/var/log/vps_setup.log"

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

ask_new_user() {
    local answer

    while true; do
        read -r -p "Введите имя нового пользователя [$DEFAULT_NEW_USER]: " answer

        if [ -z "$answer" ]; then
            answer="$DEFAULT_NEW_USER"
        fi

        if [[ "$answer" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
            NEW_USER="$answer"
            return 0
        fi

        warn "Имя пользователя должно начинаться со строчной буквы или _, затем содержать только строчные буквы, цифры, _ или -."
    done
}

ask_public_keys() {
    local answer
    PUBLIC_KEYS=()

    info "Введите публичные SSH-ключи по одному. Пустая строка — завершить ввод."
    info "Если не ввести ни одного ключа, будут использованы ключи по умолчанию."

    while true; do
        read -r -p "SSH-ключ #$(( ${#PUBLIC_KEYS[@]} + 1 )) (Enter — закончить): " answer

        # Пустая строка завершает ввод
        if [ -z "$answer" ]; then
            if [ "${#PUBLIC_KEYS[@]}" -eq 0 ]; then
                PUBLIC_KEYS=("${DEFAULT_PUBLIC_KEYS[@]}")
                info "Ключи не введены → используются ключи по умолчанию (${#PUBLIC_KEYS[@]} шт.)"
            fi
            return 0
        fi

        if [[ ! "$answer" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
            warn "SSH-ключ должен начинаться с ssh-rsa, ssh-ed25519 или ssh-ecdsa."
            continue
        fi

        # Пропускаем дубликаты
        local dup=0 existing
        for existing in "${PUBLIC_KEYS[@]}"; do
            if [ "$existing" = "$answer" ]; then
                dup=1
                break
            fi
        done
        if [ "$dup" -eq 1 ]; then
            warn "Такой ключ уже добавлен → пропускаю."
            continue
        fi

        PUBLIC_KEYS+=("$answer")
        success "Добавлен ключ #${#PUBLIC_KEYS[@]}"
    done
}

ask_ssh_port() {
    local answer

    while true; do
        read -r -p "Введите порт SSH [$SSH_PORT]: " answer

        if [ -z "$answer" ]; then
            answer="$SSH_PORT"
        fi

        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le 65535 ]; then
            SSH_PORT="$answer"
            return 0
        fi

        warn "Порт SSH должен быть числом от 1 до 65535."
    done
}

if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт должен запускаться от root."
    exit 1
fi

# Дублируем весь вывод в лог-файл (нужны права root для записи в /var/log)
exec > >(tee -a "$LOG_FILE") 2>&1

ask_new_user
ask_public_keys

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

if [ "$HARDEN_SSH" = "1" ]; then
    ask_ssh_port
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

if ! ask_yes_no "Запустить первичную настройку VPS? [y/N]" "n"; then
    warn "Отменено."
    exit 0
fi

# 1. Обновление системы
info "1. Обновление и апгрейд пакетов без вопросов, сохраняем свои конфиги..."
apt update
apt upgrade -y \
-o Dpkg::Options::="--force-confdef" \
-o Dpkg::Options::="--force-confold"

# 2. Установка вспомогательных пакетов
info "2. Установка вспомогательных пакетов..."
apt install -y \
curl \
ca-certificates \
mc \
htop \
btop \
iftop \
bat \
micro

# 3. Установка Docker — только если его нет
info "3. Проверка и установка Docker (если требуется)..."

if command -v docker >/dev/null 2>&1; then
    success "Docker уже установлен → пропускаем установку"
    systemctl is-active --quiet docker || systemctl start docker
    systemctl enable docker
else
    info "Docker не найден → выполняем установку..."
    tmp_docker="$(mktemp)"
    curl -fsSL https://get.docker.com -o "$tmp_docker"
    sh "$tmp_docker"
    rm -f "$tmp_docker"

    # Запуск и автозапуск
    systemctl start docker
    systemctl enable docker
fi

if systemctl is-active --quiet docker; then
    success "Docker установлен и запущен"
else
    error "Docker не запустился — проверьте: systemctl status docker"
    exit 1
fi

# 4. Создание пользователя
info "4. Создание пользователя $NEW_USER (без пароля)..."
if id "$NEW_USER" >/dev/null 2>&1; then
    warn "Пользователь $NEW_USER уже существует → пропускаем создание"
else
    adduser --disabled-password --gecos "" "$NEW_USER"
fi
printf "alias lss='ls -lah --group-directories-first'\nalias cls='clear'\nalias ip='ip -c'\nalias df='df -h'\n" | su - "$NEW_USER" -c "tee ~/.bash_aliases > /dev/null"
su - "$NEW_USER" -c "chmod 644 ~/.bash_aliases"
success "Для пользователя $NEW_USER создан файл ~/.bash_aliases"

# 5. Добавление в группы sudo и docker
usermod -aG sudo   "$NEW_USER"
usermod -aG docker "$NEW_USER"
success "Пользователь $NEW_USER добавлен в группы sudo и docker"

# 6. Добавление SSH-ключей в authorized_keys
info "6. Добавление публичных SSH-ключей для $NEW_USER (${#PUBLIC_KEYS[@]} шт.)..."
su - "$NEW_USER" -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
for key in "${PUBLIC_KEYS[@]}"; do
    if su - "$NEW_USER" -c "grep -qxF '$key' ~/.ssh/authorized_keys"; then
        success "Ключ уже присутствует → пропускаем: ${key%% *} ...${key##* }"
    else
        echo "$key" | su - "$NEW_USER" -c "tee -a ~/.ssh/authorized_keys > /dev/null"
        success "Ключ успешно добавлен: ${key%% *} ...${key##* }"
    fi
done

# 7. sudo без пароля
info "7. Настройка sudo без пароля для $NEW_USER..."
echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" | tee "/etc/sudoers.d/$NEW_USER" >/dev/null
chmod 0440 "/etc/sudoers.d/$NEW_USER"
# Проверяем синтаксис sudoers, чтобы не сломать sudo целиком
if ! visudo -cf "/etc/sudoers.d/$NEW_USER" >/dev/null; then
    error "Некорректный файл sudoers — удаляю его."
    rm -f "/etc/sudoers.d/$NEW_USER"
    exit 1
fi
success "sudo без пароля настроен"

# 8. Настройка SSH (условно, в зависимости от HARDEN_SSH)
if [ "$HARDEN_SSH" = "1" ]; then
    info "8. Настройка SSH: отключение root-доступа, входа по паролю, смена порта на $SSH_PORT"

    # Убеждаемся, что ключ на месте, ПРЕЖДЕ чем отключать парольный вход
    if ! su - "$NEW_USER" -c "test -s ~/.ssh/authorized_keys"; then
        error "authorized_keys пуст — отключение пароля заблокирует доступ. Прерываю."
        exit 1
    fi

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

    # Если активен ufw — открываем новый порт, иначе после рестарта потеряем доступ
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        info "ufw активен → открываю порт $SSH_PORT/tcp"
        ufw allow "$SSH_PORT"/tcp
    fi

    # Определяем фактическое имя сервиса SSH (ssh на Debian/Ubuntu, иногда sshd)
    SSH_SERVICE="ssh"
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        SSH_SERVICE="sshd"
    fi

    # На новых Ubuntu (22.10+) SSH активируется через сокет, и Port из sshd_config
    # игнорируется. Переключаемся на обычный сервис, чтобы новый порт применился.
    if systemctl is-enabled --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh.socket 2>/dev/null; then
        warn "Обнаружен ssh.socket → переключаюсь на сервис $SSH_SERVICE, чтобы порт применился"
        systemctl disable --now ssh.socket 2>/dev/null || true
        systemctl enable "$SSH_SERVICE" 2>/dev/null || true
    fi

    # Проверяем конфиг ДО перезапуска — иначе можно заблокировать себе доступ
    if ! sshd -t; then
        error "Конфигурация SSH невалидна — откатываю изменения."
        rm -f /etc/ssh/sshd_config.d/01-custom-ssh-settings.conf
        exit 1
    fi

    # Перезапускаем SSH сервис
    systemctl restart "$SSH_SERVICE"

    success "SSH настроен: порт $SSH_PORT, root-доступ отключён, вход по паролю отключён"
    warn "НЕ ЗАКРЫВАЙТЕ текущую сессию! Сначала проверьте вход в новом окне:"
    warn "    ssh -p $SSH_PORT $NEW_USER@<IP-адрес-сервера>"
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
