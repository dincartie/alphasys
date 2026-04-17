#!/bin/bash
# =============================================================================
#  alphasys — CLI-утилита автоматической настройки сетевой инфраструктуры
#  Демоэкзамен ФГОС 09.02.06, ALT Server/Workstation 11.x
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/resources"
VERSION="1.0.0"
ERRORS=0

# ─────────────────────────────────────────────── Цвета и форматирование
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_RED="\033[0;31m"
CLR_GREEN="\033[0;32m"
CLR_YELLOW="\033[0;33m"
CLR_CYAN="\033[0;36m"
CLR_DIM="\033[2m"

# ─────────────────────────────────────────────────────── Логика вывода
VERBOSE=0  # устанавливается флагом --output

log_info() { [ "$VERBOSE" -eq 1 ] && printf "  ${CLR_CYAN}→${CLR_RESET} %s\n" "$*"; }
log_ok()   { [ "$VERBOSE" -eq 1 ] && printf "  ${CLR_GREEN}✓${CLR_RESET} %s\n" "$*"; }
log_warn() { [ "$VERBOSE" -eq 1 ] && printf "  ${CLR_YELLOW}!${CLR_RESET} %s\n" "$*"; }
log_err()  { [ "$VERBOSE" -eq 1 ] && printf "  ${CLR_RED}✗${CLR_RESET} %s\n" "$*"; ERRORS=$((ERRORS+1)); }
log_step() { [ "$VERBOSE" -eq 1 ] && printf "\n${CLR_BOLD}[ %s ]${CLR_RESET}\n" "$*"; }
log_svc()  {
    if [ "$VERBOSE" -eq 1 ]; then
        local svc="$1"
        local status
        status=$(systemctl is-active "$svc" 2>/dev/null)
        if [ "$status" = "active" ]; then
            printf "  ${CLR_GREEN}●${CLR_RESET} %-16s %s\n" "$svc" "active"
        else
            printf "  ${CLR_RED}●${CLR_RESET} %-16s %s\n" "$svc" "${status:-unknown}"
        fi
    fi
}

run() {
    local desc="$1"; shift
    log_info "$desc"
    if "$@" >> /tmp/alphasys.log 2>&1; then
        log_ok "$desc"
        return 0
    else
        log_err "Ошибка: $desc"
        return 1
    fi
}

copy_file() {
    local src="$1" dst="$2"
    log_info "Копирование → $dst"
    mkdir -p "$(dirname "$dst")"
    if cp "$src" "$dst"; then
        log_ok "$dst"
    else
        log_err "Не удалось: $src → $dst"
    fi
}

copy_tree() {
    local src_base="$1"
    find "$src_base" -type f | while read -r src_file; do
        local rel="${src_file#$src_base}"
        copy_file "$src_file" "/${rel}"
    done
}

# ──────────────────────────────────────────────────── Показать заставку
show_about() {
cat <<EOF

${CLR_BOLD}  alphasys${CLR_RESET} v${VERSION}
  ${CLR_DIM}Network deployment & administration utility${CLR_RESET}
  ${CLR_DIM}Демоэкзамен ФГОС 09.02.06 — Сетевое и системное администрирование${CLR_RESET}

  Использование: ${CLR_BOLD}bash alphasys -id=<ID> -mod=<MODULE> [--output]${CLR_RESET}

  Доступные машины:
    ${CLR_CYAN}100${CLR_RESET}  ISP      — Провайдер (NAT, маршрутизация)
    ${CLR_CYAN}101${CLR_RESET}  HQ-RTR   — Маршрутизатор головного офиса
    ${CLR_CYAN}102${CLR_RESET}  BR-RTR   — Маршрутизатор филиала
    ${CLR_CYAN}103${CLR_RESET}  HQ-SRV   — Сервер головного офиса (DNS, SSH)
    ${CLR_CYAN}104${CLR_RESET}  BR-SRV   — Сервер филиала (SSH)
    ${CLR_CYAN}105${CLR_RESET}  HQ-CLI   — Рабочая станция головного офиса

  Модули:
    ${CLR_CYAN}network_setup${CLR_RESET}  — Начальная настройка сети
    ${CLR_CYAN}network_admin${CLR_RESET}  — Администрирование сети
    ${CLR_CYAN}hybrid${CLR_RESET}         — Оба модуля

  Подробнее: ${CLR_BOLD}bash alphasys --help${CLR_RESET}

EOF
}

show_help() {
cat <<EOF

${CLR_BOLD}Usage:${CLR_RESET} alphasys [options]

${CLR_BOLD}DESCRIPTION:${CLR_RESET}
  A utility designed for deploying and administering network
  components on target machines by their identifier.

${CLR_BOLD}Options:${CLR_RESET}
  ${CLR_CYAN}-id=<N>${CLR_RESET}            Machine identifier (Required when using -mod).
  ${CLR_CYAN}-mod, --module${CLR_RESET}     Module to execute. Available values:
                       network_setup : Initial network configuration,
                       network_admin : Network administration,
                       hybrid        : Mixed operation mode.
                       (Only one module can be selected).
  ${CLR_CYAN}-o, --output${CLR_RESET}       Enable verbose output for script operations.
  ${CLR_CYAN}-h, --help${CLR_RESET}         Show this help message.

${CLR_BOLD}Examples:${CLR_RESET}
  bash alphasys -id=102 -mod=hybrid --output
  bash alphasys -id=101 -mod=network_setup
  bash alphasys --help

${CLR_BOLD}Machine IDs:${CLR_RESET}
  100 = ISP | 101 = HQ-RTR | 102 = BR-RTR
  103 = HQ-SRV | 104 = BR-SRV | 105 = HQ-CLI

EOF
}

# ═══════════════════════════════════════════════ MODULE: network_setup

setup_isp() {
    log_step "ISP — Hostname"
    run "hostname: isp.au-team.irpo" hostnamectl set-hostname isp.au-team.irpo

    log_step "ISP — Сетевые интерфейсы"
    copy_tree "${RESOURCES_DIR}/network_setup/isp"
    run "sysctl ip_forward" sysctl -p /etc/net/sysctl.conf
    run "Перезапуск network" systemctl restart network

    log_step "ISP — NAT / Firewall"
    run "masquerade: external" firewall-cmd --permanent --zone=external --add-masquerade
    run "ens19 → external" firewall-cmd --permanent --zone=external --add-interface=ens19
    run "ens20 → trusted"  firewall-cmd --permanent --zone=trusted   --add-interface=ens20
    run "ens21 → trusted"  firewall-cmd --permanent --zone=trusted   --add-interface=ens21
    run "Перезапуск firewalld" systemctl restart firewalld

    run "Часовой пояс Europe/Moscow" timedatectl set-timezone Europe/Moscow

    log_step "ISP — Сервисы"
    log_svc network; log_svc firewalld
}

setup_hq_rtr() {
    log_step "HQ-RTR — Hostname"
    run "hostname: hq-rtr.au-team.irpo" hostnamectl set-hostname hq-rtr.au-team.irpo

    log_step "HQ-RTR — Сетевые интерфейсы / VLAN / GRE"
    copy_tree "${RESOURCES_DIR}/network_setup/headquarters/router"
    run "sysctl ip_forward" sysctl -p /etc/net/sysctl.conf
    run "Перезапуск network" systemctl restart network

    log_step "HQ-RTR — Пользователь net_admin"
    id net_admin &>/dev/null || run "useradd net_admin" useradd net_admin -m -U -s /bin/bash
    run "passwd net_admin" bash -c "echo 'net_admin:P@ssw0rd' | chpasswd"
    run "wheel: net_admin"  usermod -aG wheel net_admin

    log_step "HQ-RTR — FRR / OSPF"
    command -v vtysh &>/dev/null || run "Установка frr" apt-get install -y frr
    run "enable frr"  systemctl enable frr
    run "restart frr" systemctl restart frr

    log_step "HQ-RTR — Firewall / NAT"
    run "gre protocol"      firewall-cmd --permanent --add-protocol=gre
    run "tun1 → trusted"    firewall-cmd --permanent --zone=trusted   --add-interface=tun1
    run "masquerade"        firewall-cmd --permanent --zone=external   --add-masquerade
    run "ens19 → external"  firewall-cmd --permanent --zone=external   --add-interface=ens19
    run "Перезапуск firewalld" systemctl restart firewalld

    log_step "HQ-RTR — DHCP (ens20.200 → HQ-CLI)"
    rpm -q dhcp-server &>/dev/null || run "Установка dhcp-server" apt-get install -y dhcp-server
    run "enable dhcpd"  systemctl enable dhcpd
    run "restart dhcpd" systemctl restart dhcpd

    run "Часовой пояс Europe/Moscow" timedatectl set-timezone Europe/Moscow

    log_step "HQ-RTR — Сервисы"
    log_svc network; log_svc firewalld; log_svc frr; log_svc dhcpd
}

setup_br_rtr() {
    log_step "BR-RTR — Hostname"
    run "hostname: br-rtr.au-team.irpo" hostnamectl set-hostname br-rtr.au-team.irpo

    log_step "BR-RTR — Сетевые интерфейсы / GRE"
    copy_tree "${RESOURCES_DIR}/network_setup/branch/router"
    run "sysctl ip_forward" sysctl -p /etc/net/sysctl.conf
    run "Перезапуск network" systemctl restart network

    log_step "BR-RTR — Пользователь net_admin"
    id net_admin &>/dev/null || run "useradd net_admin" useradd net_admin -m -U -s /bin/bash
    run "passwd net_admin" bash -c "echo 'net_admin:P@ssw0rd' | chpasswd"
    run "wheel: net_admin"  usermod -aG wheel net_admin

    log_step "BR-RTR — FRR / OSPF"
    command -v vtysh &>/dev/null || run "Установка frr" apt-get install -y frr
    run "enable frr"  systemctl enable frr
    run "restart frr" systemctl restart frr

    log_step "BR-RTR — Firewall / NAT"
    run "gre protocol"      firewall-cmd --permanent --add-protocol=gre
    run "tun1 → trusted"    firewall-cmd --permanent --zone=trusted   --add-interface=tun1
    run "masquerade"        firewall-cmd --permanent --zone=external   --add-masquerade
    run "ens19 → external"  firewall-cmd --permanent --zone=external   --add-interface=ens19
    run "Перезапуск firewalld" systemctl restart firewalld

    run "Часовой пояс Europe/Moscow" timedatectl set-timezone Europe/Moscow

    log_step "BR-RTR — Сервисы"
    log_svc network; log_svc firewalld; log_svc frr
}

setup_hq_srv() {
    log_step "HQ-SRV — Hostname"
    run "hostname: hq-srv.au-team.irpo" hostnamectl set-hostname hq-srv.au-team.irpo

    log_step "HQ-SRV — Сетевые интерфейсы"
    copy_tree "${RESOURCES_DIR}/network_setup/headquarters/server"
    run "Перезапуск network" systemctl restart network

    log_step "HQ-SRV — Пользователь sshuser"
    id sshuser &>/dev/null || run "useradd sshuser" useradd sshuser -m -U -s /bin/bash
    run "passwd sshuser"   bash -c "echo 'sshuser:P@ssw0rd' | chpasswd"
    run "UID 2026"         usermod -u 2026 sshuser
    run "wheel: sshuser"   usermod -aG wheel sshuser

    log_step "HQ-SRV — SSH"
    run "enable sshd"  systemctl enable sshd
    run "restart sshd" systemctl restart sshd
    run "fw: порт 2026/tcp"   firewall-cmd --permanent --add-port=2026/tcp
    run "Перезапуск firewalld" systemctl restart firewalld

    log_step "HQ-SRV — DNS (BIND)"
    rpm -q bind &>/dev/null || run "Установка bind" apt-get install -y bind
    run "enable bind"  bash -c "systemctl enable bind 2>/dev/null || systemctl enable named"
    run "restart bind" bash -c "systemctl restart bind 2>/dev/null || systemctl restart named"

    run "Часовой пояс Europe/Moscow" timedatectl set-timezone Europe/Moscow

    log_step "HQ-SRV — Сервисы"
    log_svc network; log_svc firewalld; log_svc sshd; log_svc bind
}

setup_br_srv() {
    log_step "BR-SRV — Hostname"
    run "hostname: br-srv.au-team.irpo" hostnamectl set-hostname br-srv.au-team.irpo

    log_step "BR-SRV — Сетевые интерфейсы"
    copy_tree "${RESOURCES_DIR}/network_setup/branch/server"
    run "Перезапуск network" systemctl restart network

    log_step "BR-SRV — Пользователь sshuser"
    id sshuser &>/dev/null || run "useradd sshuser" useradd sshuser -m -U -s /bin/bash
    run "passwd sshuser"  bash -c "echo 'sshuser:P@ssw0rd' | chpasswd"
    run "UID 2026"        usermod -u 2026 sshuser
    run "wheel: sshuser"  usermod -aG wheel sshuser

    log_step "BR-SRV — SSH"
    run "enable sshd"  systemctl enable sshd
    run "restart sshd" systemctl restart sshd
    run "fw: порт 2026/tcp"   firewall-cmd --permanent --add-port=2026/tcp
    run "Перезапуск firewalld" systemctl restart firewalld

    run "Часовой пояс Europe/Moscow" timedatectl set-timezone Europe/Moscow

    log_step "BR-SRV — Сервисы"
    log_svc network; log_svc firewalld; log_svc sshd
}

setup_hq_cli() {
    log_step "HQ-CLI — Hostname"
    run "hostname: hq-cli.au-team.irpo" hostnamectl set-hostname hq-cli.au-team.irpo
    run "Часовой пояс Europe/Moscow" timedatectl set-timezone Europe/Moscow
    log_warn "Сеть HQ-CLI получает адрес по DHCP от HQ-RTR (ens20.200 / VLAN 200)."
    log_svc network
}

# ═════════════════════════════════════════════ MODULE: network_admin
run_network_admin() {
    local mid="$1"
    log_step "network_admin — Диагностика ID=${mid}"
    local -a svcs=()
    case "$mid" in
        100) svcs=(network firewalld) ;;
        101) svcs=(network firewalld frr dhcpd) ;;
        102) svcs=(network firewalld frr) ;;
        103) svcs=(network firewalld sshd bind) ;;
        104) svcs=(network firewalld sshd) ;;
        105) svcs=(network) ;;
    esac
    log_step "network_admin — Сервисы"
    for svc in "${svcs[@]}"; do log_svc "$svc"; done
    if [ "$VERBOSE" -eq 1 ]; then
        printf "\n${CLR_BOLD}[ network_admin — Адреса ]${CLR_RESET}\n"
        ip -brief addr show 2>/dev/null
        printf "\n${CLR_BOLD}[ network_admin — Маршруты ]${CLR_RESET}\n"
        ip route show 2>/dev/null
    fi
}

run_network_setup() {
    case "$1" in
        100) setup_isp ;;
        101) setup_hq_rtr ;;
        102) setup_br_rtr ;;
        103) setup_hq_srv ;;
        104) setup_br_srv ;;
        105) setup_hq_cli ;;
    esac
}

# ════════════════════════════════════════════════════════ АРГУМЕНТЫ
ARG_ID=""
ARG_MOD=""
ARG_HELP=0

for arg in "$@"; do
    case "$arg" in
        -id=*)             ARG_ID="${arg#-id=}" ;;
        -mod=*|--module=*) ARG_MOD="${arg#*=}" ;;
        -o|--output)       VERBOSE=1 ;;
        -h|--help)         ARG_HELP=1 ;;
        *)
            printf "Ошибка: Неизвестный аргумент: %s\n" "$arg" >&2
            exit 1 ;;
    esac
done

# Г. -h + другие флаги → ошибка
if [ "$ARG_HELP" -eq 1 ] && { [ -n "$ARG_ID" ] || [ -n "$ARG_MOD" ] || [ "$VERBOSE" -eq 1 ]; }; then
    printf "Ошибка: Несовместимые флаги. Пожалуйста, уберите флаг -h для выполнения команды или уберите остальные флаги для просмотра справки.\n" >&2
    exit 1
fi
[ "$ARG_HELP" -eq 1 ] && { show_help; exit 0; }

# А. Нет аргументов → about
[ "$#" -eq 0 ] && { show_about; exit 0; }
[ "$VERBOSE" -eq 1 ] && [ -z "$ARG_ID" ] && [ -z "$ARG_MOD" ] && { show_about; exit 0; }

# Б. -id без -mod
[ -n "$ARG_ID" ] && [ -z "$ARG_MOD" ] && {
    printf "Ошибка: Параметр -id не может быть использован без указания модуля (-mod).\n" >&2; exit 1; }

# Б. -mod без -id
[ -n "$ARG_MOD" ] && [ -z "$ARG_ID" ] && {
    printf "Ошибка: Для работы модуля необходимо указать идентификатор машины (-id).\n" >&2; exit 1; }

# В. Проверка модуля
case "$ARG_MOD" in
    network_setup|network_admin|hybrid) ;;
    *,*|*\ *)
        printf "Ошибка: Допустимо указать только один модуль. Доступные: network_setup, network_admin, hybrid.\n" >&2; exit 1 ;;
    *)
        printf "Ошибка: Неизвестный модуль '%s'. Доступные: network_setup, network_admin, hybrid.\n" "$ARG_MOD" >&2; exit 1 ;;
esac

# Проверка ID
case "$ARG_ID" in
    100|101|102|103|104|105) ;;
    *)
        printf "Ошибка: Неизвестный ID '%s'. Допустимые: 100–105.\n" "$ARG_ID" >&2; exit 1 ;;
esac

# ════════════════════════════════════════════════════════════ ЗАПУСК
: > /tmp/alphasys.log

[ "$VERBOSE" -eq 1 ] && printf "\n${CLR_BOLD}  alphasys${CLR_RESET} ${CLR_DIM}v${VERSION}${CLR_RESET}  id=${CLR_CYAN}${ARG_ID}${CLR_RESET}  mod=${CLR_CYAN}${ARG_MOD}${CLR_RESET}\n"

case "$ARG_MOD" in
    network_setup) run_network_setup "$ARG_ID" ;;
    network_admin) run_network_admin "$ARG_ID" ;;
    hybrid)
        run_network_setup "$ARG_ID"
        run_network_admin "$ARG_ID" ;;
esac

# ════════════════════════════════════════════════════════════════ ИТОГ
[ "$VERBOSE" -eq 1 ] && printf "\n"
if [ "$ERRORS" -eq 0 ]; then
    [ "$VERBOSE" -eq 1 ] && printf "${CLR_GREEN}${CLR_BOLD}  alphasys: success.${CLR_RESET}\n\n" \
                         || printf "alphasys: success.\n"
else
    [ "$VERBOSE" -eq 1 ] && printf "${CLR_RED}${CLR_BOLD}  alphasys: failed.${CLR_RESET}${CLR_DIM}  ошибок: ${ERRORS} | лог: /tmp/alphasys.log${CLR_RESET}\n\n" \
                         || printf "alphasys: failed.\n"
fi

exit "$ERRORS"
