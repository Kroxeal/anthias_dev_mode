#!/bin/bash -e

# vim: tabstop=4 shiftwidth=4 softtabstop=4
# -*- sh-basic-offset: 4 -*-

set -euo pipefail

# Проверка на Raspberry Pi 4B
if ! grep -q "Raspberry Pi 4" /proc/device-tree/model && ! grep -q "Compute Module 4" /proc/device-tree/model; then
    echo "Ошибка: Этот скрипт предназначен только для Raspberry Pi 4B"
    exit 1
fi

# Проверка архитектуры
if [ "$(uname -m)" != "aarch64" ]; then
    echo "Ошибка: Этот скрипт предназначен только для ARM64 архитектуры"
    exit 1
fi

BRANCH="master"
ANSIBLE_PLAYBOOK_ARGS=()
REPOSITORY="https://github.com/Kroxeal/anthias_dev_mode.git"
ANTHIAS_REPO_DIR="/home/${USER}/screenly"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Kroxeal/anthias_dev_mode"

DISTRO_VERSION=$(lsb_release -rs)
ARCHITECTURE=$(uname -m)

INTRO_MESSAGE=(
    "Anthias Dev Mode установщик для Raspberry Pi 4B"
    "После установки вы не сможете использовать обычный рабочий стол."
    ""
    "Установка будет произведена из ветки master."
)

MANAGE_NETWORK_PROMPT=(
    "Хотите ли вы, чтобы Anthias управлял сетью?"
)

SYSTEM_UPGRADE_PROMPT=(
    "Хотите ли вы выполнить полное обновление системы?"
)

SUDO_ARGS=()

TITLE_TEXT=$(cat <<EOF
     @@@@@@@@@
  @@@@@@@@@@@@                 d8888          888    888      d8b
 @@@@@@@  @@@    @@           d88888          888    888      Y8P
@@@@@@@@@@@@@    @@@         d88P888          888    888
@@@@@@@@@@ @@   @@@@        d88P 888 88888b.  888888 88888b.  888  8888b.  .d8888b
@@@@@       @@@@@@@@       d88P  888 888 "88b 888    888 "88b 888     "88b 88K
@@@%:      :@@@@@@@@      d88P   888 888  888 888    888  888 888 .d888888 "Y8888b.
 @@-:::::::%@@@@@@@      d8888888888 888  888 Y88b.  888  888 888 888  888      X88
  @=::::=%@@@@@@@@      d88P     888 888  888  "Y888 888  888 888 "Y888888  88888P'
     @@@@@@@@@@
EOF
)

# Install gum from Charm.sh.
# Gum helps you write shell scripts more efficiently.
function install_prerequisites() {
    if [ -f /usr/bin/gum ] && [ -f /usr/bin/jq ]; then
        return
    fi

    sudo apt -y update && sudo apt -y install gnupg

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | \
        sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        | sudo tee /etc/apt/sources.list.d/charm.list

    sudo apt -y update && sudo apt -y install gum jq
}

function display_banner() {
    local TITLE="${1:-Anthias Installer}"
    local COLOR="212"

    gum style \
        --foreground "${COLOR}" \
        --border-foreground "${COLOR}" \
        --border "thick" \
        --margin "1 1" \
        --padding "2 6" \
        "${TITLE}"
}

function display_section() {
    local TITLE="${1:-Section}"
    local COLOR="#00FFFF"

    gum style \
        --foreground "${COLOR}" \
        --border-foreground "${COLOR}" \
        --border "thick" \
        --align center \
        --width 95 \
        --margin "1 1" \
        --padding "1 4" \
        "${TITLE}"
}

function initialize_ansible() {
    sudo mkdir -p /etc/ansible
    echo -e "[local]\nlocalhost ansible_connection=local" | \
        sudo tee /etc/ansible/hosts > /dev/null
}

function initialize_locales() {
    display_section "Инициализация локалей"

    if [ ! -f /etc/locale.gen ]; then
        echo -e "en_GB.UTF-8 UTF-8\nen_US.UTF-8 UTF-8" | \
            sudo tee /etc/locale.gen > /dev/null
        sudo locale-gen
    fi
}

function install_packages() {
    display_section "Установка пакетов через APT"

    local APT_INSTALL_ARGS=(
        "git"
        "libffi-dev"
        "libssl-dev"
        "whois"
    )

    if [ "$DISTRO_VERSION" -ge 12 ]; then
        APT_INSTALL_ARGS+=(
            "python3-dev"
            "python3-full"
        )
    else
        APT_INSTALL_ARGS+=(
            "python3"
            "python3-dev"
            "python3-pip"
            "python3-venv"
        )
    fi

    if [ "$MANAGE_NETWORK" = "Yes" ]; then
        APT_INSTALL_ARGS+=("network-manager")
    fi

    sudo apt update -y
    sudo apt-get install -y "${APT_INSTALL_ARGS[@]}"
}

function install_ansible() {
    display_section "Установка Ansible"

    REQUIREMENTS_URL="$GITHUB_RAW_URL/$BRANCH/requirements/requirements.host.txt"
    if [ "$DISTRO_VERSION" -le 11 ]; then
        ANSIBLE_VERSION="ansible-core==2.15.9"
    else
        ANSIBLE_VERSION=$(curl -s $REQUIREMENTS_URL | grep ansible)
    fi

    SUDO_ARGS=()

    if python3 -c "import venv" &> /dev/null; then
        gum format 'Модуль `venv` обнаружен. Активация виртуального окружения...'
        echo

        python3 -m venv /home/${USER}/installer_venv
        source /home/${USER}/installer_venv/bin/activate

        SUDO_ARGS+=("--preserve-env" "env" "PATH=$PATH")
    fi

    sudo ${SUDO_ARGS[@]} pip install cryptography==38.0.1
    sudo ${SUDO_ARGS[@]} pip install "$ANSIBLE_VERSION"
}

function set_device_type() {
    export DEVICE_TYPE="pi4"
}

function run_ansible_playbook() {
    display_section "Запуск Ansible Playbook для Anthias"
    set_device_type

    sudo -u ${USER} ${SUDO_ARGS[@]} ansible localhost \
        -m git \
        -a "repo=$REPOSITORY dest=${ANTHIAS_REPO_DIR} version=${BRANCH} force=yes"
    cd ${ANTHIAS_REPO_DIR}/ansible

    sudo -E -u ${USER} ${SUDO_ARGS[@]} \
        ansible-playbook site.yml "${ANSIBLE_PLAYBOOK_ARGS[@]}"
}

function cleanup() {
    display_section "Очистка неиспользуемых пакетов и файлов"

    sudo apt-get autoclean
    sudo apt-get clean
    sudo apt autoremove -y
    sudo apt-get install plymouth --reinstall -y
    sudo find /usr/share/doc \
        -depth \
        -type f \
        ! -name copyright \
        -delete
    sudo find /usr/share/doc \
        -empty \
        -delete
    sudo rm -rf \
        /usr/share/man \
        /usr/share/groff \
        /usr/share/info/* \
        /usr/share/lintian \
        /usr/share/linda /var/cache/man
    sudo find /usr/share/locale \
        -type f \
        ! -name 'en' \
        ! -name 'de*' \
        ! -name 'es*' \
        ! -name 'ja*' \
        ! -name 'fr*' \
        ! -name 'zh*' \
        -delete
    sudo find /usr/share/locale \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name 'en*' \
        ! -name 'de*' \
        ! -name 'es*' \
        ! -name 'ja*' \
        ! -name 'fr*' \
        ! -name 'zh*' \
        ! -name 'locale.alias' \
        -exec rm -r {} \;
}

function modify_permissions() {
    sudo chown -R ${USER}:${USER} /home/${USER}

    if [ ! -f /etc/sudoers.d/010_${USER}-nopasswd ]; then
        echo "${USER} ALL=(ALL) NOPASSWD: ALL" | \
            sudo tee /etc/sudoers.d/010_${USER}-nopasswd > /dev/null
        sudo chmod 0440 /etc/sudoers.d/010_${USER}-nopasswd
    fi
}

function write_anthias_version() {
    local GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    local GIT_SHORT_HASH=$(git rev-parse --short HEAD)
    local ANTHIAS_VERSION="Anthias Version: ${GIT_BRANCH}@${GIT_SHORT_HASH}"

    echo "${ANTHIAS_VERSION}" > ~/version.md
    echo "$(lsb_release -a 2> /dev/null)" >> ~/version.md
}

function post_installation() {
    local POST_INSTALL_MESSAGE=()

    display_section "Установка завершена"

    if [ -f /var/run/reboot-required ]; then
        POST_INSTALL_MESSAGE+=(
            "Пожалуйста, перезагрузите систему и запустите \`${UPGRADE_SCRIPT_PATH}\` "
            "для завершения установки."
        )
    else
        POST_INSTALL_MESSAGE+=(
            "Необходимо перезагрузить систему для завершения установки."
        )
    fi

    echo

    gum style --foreground "#00FFFF" "${POST_INSTALL_MESSAGE[@]}" | gum format

    echo

    gum confirm "Хотите перезагрузить систему сейчас?" && \
        gum style --foreground "#FF00FF" "Перезагрузка..." | gum format && \
        sudo reboot
}

function main() {
    install_prerequisites && clear

    display_banner "${TITLE_TEXT}"

    gum format "${INTRO_MESSAGE[@]}"
    echo
    gum confirm "Хотите продолжить установку?" || exit 0
    
    gum confirm "${MANAGE_NETWORK_PROMPT[@]}" && \
        export MANAGE_NETWORK="Yes" || \
        export MANAGE_NETWORK="No"

    gum confirm "${SYSTEM_UPGRADE_PROMPT[@]}" && {
        SYSTEM_UPGRADE="Yes"
    } || {
        SYSTEM_UPGRADE="No"
        ANSIBLE_PLAYBOOK_ARGS+=("--skip-tags" "system-upgrade")
    }

    display_section "Сводка настроек"
    gum format "**Управление сетью:**     ${MANAGE_NETWORK}"
    gum format "**Обновление системы:**   ${SYSTEM_UPGRADE}"

    if [ ! -d "${ANTHIAS_REPO_DIR}" ]; then
        mkdir "${ANTHIAS_REPO_DIR}"
    fi

    initialize_ansible
    initialize_locales
    install_packages
    install_ansible
    run_ansible_playbook
    cleanup
    modify_permissions
    write_anthias_version
    post_installation
}

main
