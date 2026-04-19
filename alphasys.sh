#!/bin/bash

# Resolve script directory (supports symlinks via /usr/local/bin)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

RESOURCES_DIR="${SCRIPT_DIR}/resources"

# VMID - machine role mapping
declare -A VMID_ROLE=(
    [100]="isp"
    [101]="hq-rtr"
    [102]="br-rtr"
    [103]="hq-srv"
    [104]="br-srv"
    [105]="hq-cli"
)

declare -A VMID_HOSTNAME=(
    [100]="isp.au-team.irpo"
    [101]="hq-rtr.au-team.irpo"
    [102]="br-rtr.au-team.irpo"
    [103]="hq-srv.au-team.irpo"
    [104]="br-srv.au-team.irpo"
    [105]="hq-cli.au-team.irpo"
)

# Global state
MACHINE_ID=""
MODULE=""
VERBOSE=false
HAD_ERROR=false

# Timestamp helper  [HH:MM:SS UTC+N]
ts() {
    local tz_offset
    tz_offset=$(date +%z)          # e.g. +0300 or -0500
    local sign="${tz_offset:0:1}"
    local hours="${tz_offset:1:2}"
    hours="${hours#0}"             # strip leading zero - bare integer
    local formatted_tz="UTC${sign}${hours}"
    echo "[$(date +%H:%M:%S) ${formatted_tz}]"
}

# Logging helpers  — every line prefixed with [HH:MM:SS UTC+N] when -o active
_p()   { $VERBOSE && echo "$(ts) $*"; }          # raw prefixed print
info() { _p "[INFO]  $*"; }
ok()   { _p "[OK]    $*"; }
warn() { _p "[WARN]  $*"; }
err()  { $VERBOSE && echo "$(ts) [ERROR] $*" >&2; HAD_ERROR=true; }
sep()  { _p "------------------------------------------------------------"; }

# Run a command: prefix the command line, then capture output; log errors
run() {
    _p ">> $*"
    if ! "$@" >> /tmp/alphasys_run.log 2>&1; then
        err "Command failed: $*"
        return 1
    fi
    return 0
}

# Deploy a file from resources to the system path
deploy() {
    local src="$1"   # relative to RESOURCES_DIR
    local dst="$2"   # absolute destination path
    local src_path="${RESOURCES_DIR}/${src}"

    if [ ! -f "$src_path" ]; then
        err "Resource not found: ${src}"
        return 1
    fi

    local dst_dir
    dst_dir="$(dirname "$dst")"
    if [ ! -d "$dst_dir" ]; then
        info "Creating directory: ${dst_dir}"
        run mkdir -p "$dst_dir"
    fi

    info "Deploying ${src} - ${dst}"
    run cp -f "$src_path" "$dst"
}

# Create a directory on the target system
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        info "Creating directory: ${dir}"
        run mkdir -p "$dir"
    fi
}

# show_help  — layout matches cli_config+logic.md verbatim
show_help() {
    cat <<'EOF'
USAGE: alphasys [options]

DESCRIPTION:
  A utility designed for deploying and administering network
  components on target machines by their identifier.

OPTIONS:
  -id                Machine identifier (Required when using -mod).
  -mod, --module     Module to execute. Available values:
                     network_setup : Initial network configuration,
                     network_admin : Network administration,
                     hybrid        : Mixed operation mode.
                     (Only one module can be selected).
  -o, --output       Enable verbose output for script operations.
  -h, --help         Show this help message.

EXAMPLE:
  bash alphasys -id=102 -mod=hybrid --output
  bash alphasys -id=101 -mod=network_setup
  bash alphasys --help
EOF
}

# Argument parsing
parse_args() {
    local has_help=false
    local has_other=false

    for arg in "$@"; do
        case "$arg" in
            -h|--help)        has_help=true ;;
            -id=*)            has_other=true; MACHINE_ID="${arg#-id=}" ;;
            -mod=*|--module=*) has_other=true; MODULE="${arg#*=}" ;;
            -o|--output)      has_other=true; VERBOSE=true ;;
            *)
                echo "Error: Unknown option: ${arg}" >&2
                echo "Run 'alphasys --help' for usage." >&2
                exit 1
                ;;
        esac
    done

    # Rule D – help flag is exclusive
    if $has_help && $has_other; then
        echo "Error: Incompatible flags. Please remove the -h flag to execute the command or remove the other flags to view the help." >&2
        exit 1
    fi

    if $has_help; then
        show_help
        exit 0
    fi
}

# Validation
validate_args() {
    # Rule B – -id requires -mod
    if [ -n "$MACHINE_ID" ] && [ -z "$MODULE" ]; then
        echo "Error: The -id parameter cannot be used without specifying the module (-mod)." >&2
        exit 1
    fi

    # Rule B – -mod requires -id
    if [ -n "$MODULE" ] && [ -z "$MACHINE_ID" ]; then
        echo "Error: For the module to work, you must specify the machine ID (-id)." >&2
        exit 1
    fi

    # Rule C – validate module value (single, no commas or spaces)
    if [ -n "$MODULE" ]; then
        if [[ "$MODULE" == *","* ]] || [[ "$MODULE" == *" "* ]]; then
            echo "Error: Only one module can be selected at a time. Do not use commas or spaces in -mod." >&2
            exit 1
        fi
        case "$MODULE" in
            network_setup|network_admin|hybrid) ;;
            *)
                echo "Error: Unknown module '${MODULE}'. Valid options: network_setup, network_admin, hybrid." >&2
                exit 1
                ;;
        esac
    fi

    # Validate VMID
    if [ -n "$MACHINE_ID" ]; then
        if [[ ! "$MACHINE_ID" =~ ^[0-9]+$ ]]; then
            echo "Error: Machine ID must be a numeric Proxmox VMID (e.g. 101)." >&2
            exit 1
        fi
        if [ -z "${VMID_ROLE[$MACHINE_ID]+x}" ]; then
            echo "Error: Unknown machine ID '${MACHINE_ID}'. Supported IDs: 100, 101, 102, 103, 104, 105." >&2
            exit 1
        fi
    fi
}

#  module: network_setup
#  isp (VMID 100)
ns_isp() {
    info "network_setup: ${MACHINE_ID}"

    info "Setting hostname: isp.au-team.irpo"
    run hostnamectl set-hostname isp.au-team.irpo

    # ens20 (to HQ-RTR)
    info "Configuring ens20 - 172.16.1.1/28"
    ensure_dir /etc/net/ifaces/ens20
    deploy "network_setup/isp/etc/net/ifaces/ens20/options"     /etc/net/ifaces/ens20/options
    deploy "network_setup/isp/etc/net/ifaces/ens20/ipv4address" /etc/net/ifaces/ens20/ipv4address

    # ens21 (to BR-RTR)
    info "Configuring ens21 - 172.16.2.1/28"
    ensure_dir /etc/net/ifaces/ens21
    deploy "network_setup/isp/etc/net/ifaces/ens21/options"     /etc/net/ifaces/ens21/options
    deploy "network_setup/isp/etc/net/ifaces/ens21/ipv4address" /etc/net/ifaces/ens21/ipv4address

    # IP forwarding
    info "Enabling IPv4 forwarding"
    deploy "network_setup/isp/etc/net/sysctl.conf" /etc/net/sysctl.conf

    info "Restarting network"
    run systemctl restart network

    # firewalld + masquerade (NAT/PAT for HQ and BR)
    info "Installing firewalld"
    run apt-get install -y firewalld

    info "Enabling and starting firewalld"
    run systemctl enable --now firewalld

    info "Configuring firewall zones and masquerade (SNAT/PAT)"
    run firewall-cmd --permanent --zone=public  --add-interface=ens19
    run firewall-cmd --permanent --zone=trusted --add-interface=ens20
    run firewall-cmd --permanent --zone=trusted --add-interface=ens21
    run firewall-cmd --permanent --zone=public  --add-masquerade
    run systemctl restart firewalld

    ok "100 VMID network setup complete."
}

#  hq-rtr (VMID 101)
ns_hq_rtr() {
    info "network_setup: ${MACHINE_ID}"

    info "Setting hostname: hq-rtr.au-team.irpo"
    run hostnamectl set-hostname hq-rtr.au-team.irpo

    # ens19 (uplink to ISP)
    info "Configuring ens19 - 172.16.1.2/28, gateway 172.16.1.1"
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens19/options"      /etc/net/ifaces/ens19/options
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens19/ipv4address"  /etc/net/ifaces/ens19/ipv4address
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens19/ipv4route"    /etc/net/ifaces/ens19/ipv4route
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens19/resolv.conf"  /etc/net/ifaces/ens19/resolv.conf

    # ens20 (trunk, parent for VLANs)
    info "Configuring ens20 trunk (parent interface for VLANs)"
    ensure_dir /etc/net/ifaces/ens20
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens20/options" /etc/net/ifaces/ens20/options

    # ens20.100 – VLAN 100 (HQ-SRV segment, /27)
    info "Configuring ens20.100 - 192.168.10.1/27 (VLAN 100)"
    ensure_dir /etc/net/ifaces/ens20.100
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens20.100/options"     /etc/net/ifaces/ens20.100/options
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens20.100/ipv4address" /etc/net/ifaces/ens20.100/ipv4address

    # ens20.200 – VLAN 200 (HQ-CLI segment, /28)
    info "Configuring ens20.200 - 192.168.20.1/28 (VLAN 200)"
    ensure_dir /etc/net/ifaces/ens20.200
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens20.200/options"     /etc/net/ifaces/ens20.200/options
    deploy "network_setup/headquarters/router/etc/net/ifaces/ens20.200/ipv4address" /etc/net/ifaces/ens20.200/ipv4address

    # GRE tunnel (tun1)
    info "Configuring GRE tunnel tun1 - 10.10.10.1/30 (remote: 172.16.2.2)"
    ensure_dir /etc/net/ifaces/tun1
    deploy "network_setup/headquarters/router/etc/net/ifaces/tun1/options"     /etc/net/ifaces/tun1/options
    deploy "network_setup/headquarters/router/etc/net/ifaces/tun1/ipv4address" /etc/net/ifaces/tun1/ipv4address

    # IP forwarding
    info "Enabling IPv4 forwarding"
    deploy "network_setup/headquarters/router/etc/net/sysctl.conf" /etc/net/sysctl.conf

    info "Restarting network"
    run systemctl restart network

    # firewalld + masquerade
    info "Installing firewalld"
    run apt-get install -y firewalld

    info "Enabling and starting firewalld"
    run systemctl enable --now firewalld

    info "Configuring firewall zones and masquerade"
    run firewall-cmd --permanent --zone=public  --add-interface=ens19
    run firewall-cmd --permanent --zone=trusted --add-interface=ens20.100
    run firewall-cmd --permanent --zone=trusted --add-interface=ens20.200
    run firewall-cmd --permanent --zone=trusted --add-interface=tun1
    run firewall-cmd --permanent --zone=public  --add-masquerade
    run firewall-cmd --permanent --add-protocol=gre

    # OSPF forwarding rules
    info "Adding OSPF / GRE firewall forwarding rules"
    run firewall-cmd --permanent --zone=trusted --add-port=89/tcp
    run firewall-cmd --permanent --zone=trusted --add-port=89/udp
    run firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 \
        -i ens19 -o tun1 -j ACCEPT
    run firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 \
        -i tun1 -o ens19 -j ACCEPT
    run systemctl restart firewalld

    # frr / OSPF
    info "Installing frr for OSPF dynamic routing"
    run apt-get install -y frr

    info "Deploying frr daemons config (ospfd=yes)"
    deploy "network_setup/headquarters/router/etc/frr/daemons" /etc/frr/daemons
    deploy "network_setup/headquarters/router/etc/frr/frr.conf" /etc/frr/frr.conf

    info "Enabling and starting frr"
    run systemctl enable --now frr

    # dhcp-server for hq-cli (VLAN 200)
    info "Installing dhcp-server"
    run apt-get install -y dhcp-server

    info "Deploying dhcp-server configuration"
    ensure_dir /etc/sysconfig
    deploy "network_setup/headquarters/router/etc/sysconfig/dhcpd"  /etc/sysconfig/dhcpd
    ensure_dir /etc/dhcp
    deploy "network_setup/headquarters/router/etc/dhcp/dhcpd.conf"  /etc/dhcp/dhcpd.conf

    info "Enabling and starting dhcpd"
    run systemctl enable --now dhcpd

    ok "102 VMID network setup complete."
}


#  hq-srv (VMID 103)
ns_hq_srv() {
    info "network_setup: ${MACHINE_ID}"

    info "Setting hostname: hq-srv.au-team.irpo"
    run hostnamectl set-hostname hq-srv.au-team.irpo

    # ens19 (to HQ-RTR via VLAN 100)
    info "Configuring ens19 - 192.168.10.2/27, gateway 192.168.10.1"
    deploy "network_setup/headquarters/server/etc/net/ifaces/ens19/options"     /etc/net/ifaces/ens19/options
    deploy "network_setup/headquarters/server/etc/net/ifaces/ens19/ipv4address" /etc/net/ifaces/ens19/ipv4address
    deploy "network_setup/headquarters/server/etc/net/ifaces/ens19/ipv4route"   /etc/net/ifaces/ens19/ipv4route
    deploy "network_setup/headquarters/server/etc/net/ifaces/ens19/resolv.conf" /etc/net/ifaces/ens19/resolv.conf

    info "Restarting network"
    run systemctl restart network

    # bind
    info "Installing bind"
    run apt-get install -y bind

    info "Deploying bind options.conf (forwarder: 77.88.8.8)"
    ensure_dir /var/lib/bind/etc
    deploy "network_setup/headquarters/server/var/lib/bind/etc/options.conf" /var/lib/bind/etc/options.conf

    info "Deploying bind local zone declarations"
    deploy "network_setup/headquarters/server/var/lib/bind/etc/local.conf" /var/lib/bind/etc/local.conf

    info "Deploying DNS forward zone: au-team.irpo"
    ensure_dir /var/lib/bind/etc/zone
    deploy "network_setup/headquarters/server/var/lib/bind/etc/zone/au-team.db" /var/lib/bind/etc/zone/au-team.db

    info "Deploying DNS reverse zone: 192.168.10.x (HQ-SRV PTR)"
    deploy "network_setup/headquarters/server/var/lib/bind/etc/zone/10.db" /var/lib/bind/etc/zone/10.db

    info "Deploying DNS reverse zone: 192.168.20.x (HQ-CLI PTR)"
    deploy "network_setup/headquarters/server/var/lib/bind/etc/zone/20.db" /var/lib/bind/etc/zone/20.db

    info "Deploying DNS reverse zone: 172.16.1.x (HQ-RTR PTR)"
    deploy "network_setup/headquarters/server/var/lib/bind/etc/zone/1.db" /var/lib/bind/etc/zone/1.db

    info "Setting zone file ownership"
    run chown -R named: /var/lib/bind/etc/zone/

    # rndc.key
    info "Deploying rndc.key"
    ensure_dir /etc/bind
    deploy "network_setup/headquarters/server/etc/bind/rndc.key" /etc/bind/rndc.key

    info "Enabling and starting bind"
    run systemctl enable --now bind

    info "Restarting bind to apply zone config"
    run systemctl restart bind

    ok "104 VMID network setup complete."
}

#  hq-cli (VMID 105)
ns_hq_cli() {
    info "network_setup: ${MACHINE_ID}"
    info "Setting hostname: hq-cli.au-team.irpo"
    run hostnamectl set-hostname hq-cli.au-team.irpo

    info "HQ-CLI network interface uses DHCP (assigned by HQ-RTR)."
    info "Ensure ens19 is set to DHCP via the System Control Center GUI:"
    info "  Main Menu - Show Applications - System Control Center"
    info "  - Network - Ethernet Interfaces - Configuration: Use DHCP"
    warn "No automated network file deployment for HQ-CLI (GUI configuration required)."

    ok "105 VMID hostname set. Manual DHCP configuration required on the GUI."
}

#  br-rtr (VMID 102)
ns_br_rtr() {
    info "network_setup: ${MACHINE_ID}"

    info "Setting hostname: br-rtr.au-team.irpo"
    run hostnamectl set-hostname br-rtr.au-team.irpo

    # ens19 (uplink to ISP)
    info "Configuring ens19 - 172.16.2.2/28, gateway 172.16.2.1"
    deploy "network_setup/branch/router/etc/net/ifaces/ens19/options"     /etc/net/ifaces/ens19/options
    deploy "network_setup/branch/router/etc/net/ifaces/ens19/ipv4address" /etc/net/ifaces/ens19/ipv4address
    deploy "network_setup/branch/router/etc/net/ifaces/ens19/ipv4route"   /etc/net/ifaces/ens19/ipv4route
    deploy "network_setup/branch/router/etc/net/ifaces/ens19/resolv.conf" /etc/net/ifaces/ens19/resolv.conf

    # ens20 (to BR-SRV)
    info "Configuring ens20 - 192.168.30.1/28"
    ensure_dir /etc/net/ifaces/ens20
    deploy "network_setup/branch/router/etc/net/ifaces/ens20/options"     /etc/net/ifaces/ens20/options
    deploy "network_setup/branch/router/etc/net/ifaces/ens20/ipv4address" /etc/net/ifaces/ens20/ipv4address

    # GRE tunnel (tun1)
    info "Configuring GRE tunnel tun1 - 10.10.10.2/30 (remote: 172.16.1.2)"
    ensure_dir /etc/net/ifaces/tun1
    deploy "network_setup/branch/router/etc/net/ifaces/tun1/options"     /etc/net/ifaces/tun1/options
    deploy "network_setup/branch/router/etc/net/ifaces/tun1/ipv4address" /etc/net/ifaces/tun1/ipv4address

    # IP forwarding
    info "Enabling IPv4 forwarding"
    deploy "network_setup/branch/router/etc/net/sysctl.conf" /etc/net/sysctl.conf

    info "Restarting network"
    run systemctl restart network

    # firewalld + masquerade
    info "Installing firewalld"
    run apt-get install -y firewalld

    info "Enabling and starting firewalld"
    run systemctl enable --now firewalld

    info "Configuring firewall zones and masquerade"
    run firewall-cmd --permanent --zone=public  --add-interface=ens19
    run firewall-cmd --permanent --zone=trusted --add-interface=ens20
    run firewall-cmd --permanent --zone=trusted --add-interface=tun1
    run firewall-cmd --permanent --zone=public  --add-masquerade
    run firewall-cmd --permanent --add-protocol=gre

    # OSPF forwarding rules
    info "Adding OSPF / GRE firewall forwarding rules"
    run firewall-cmd --permanent --zone=trusted --add-port=89/tcp
    run firewall-cmd --permanent --zone=trusted --add-port=89/udp
    run firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 \
        -i ens19 -o tun1 -j ACCEPT
    run firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 \
        -i tun1 -o ens19 -j ACCEPT
    run systemctl restart firewalld

    # frr / OSPF
    info "Installing frr for OSPF dynamic routing"
    run apt-get install -y frr

    info "Deploying frr daemons config (ospfd=yes)"
    deploy "network_setup/branch/router/etc/frr/daemons"  /etc/frr/daemons
    deploy "network_setup/branch/router/etc/frr/frr.conf" /etc/frr/frr.conf

    info "Enabling and starting frr"
    run systemctl enable --now frr

    ok "102 VMID network setup complete."
}

#  br-srv (VMID 104)
ns_br_srv() {
    info "network_setup: ${MACHINE_ID}"

    info "Setting hostname: br-srv.au-team.irpo"
    run hostnamectl set-hostname br-srv.au-team.irpo

    # ens19 (to BR-RTR)
    info "Configuring ens19 - 192.168.30.2/28, gateway 192.168.30.1"
    deploy "network_setup/branch/server/etc/net/ifaces/ens19/options"     /etc/net/ifaces/ens19/options
    deploy "network_setup/branch/server/etc/net/ifaces/ens19/ipv4address" /etc/net/ifaces/ens19/ipv4address
    deploy "network_setup/branch/server/etc/net/ifaces/ens19/ipv4route"   /etc/net/ifaces/ens19/ipv4route
    deploy "network_setup/branch/server/etc/net/ifaces/ens19/resolv.conf" /etc/net/ifaces/ens19/resolv.conf

    info "Restarting network"
    run systemctl restart network

    ok "104 VMID network setup complete."
}

#  Dispatch: network_setup
run_network_setup() {
    info "module: network_setup"
    local role="${VMID_ROLE[$MACHINE_ID]}"
    case "$role" in
        isp)    ns_isp ;;
        hq-rtr) ns_hq_rtr ;;
        hq-srv) ns_hq_srv ;;
        hq-cli) ns_hq_cli ;;
        br-rtr) ns_br_rtr ;;
        br-srv) ns_br_srv ;;
    esac
}

#  module: network_admin
#  Create users on HQ-SRV / BR-SRV (sshuser, UID 2026, SSH hardening)
na_server() {
    local role="$1"   # "hq-srv" or "br-srv"
    info "network_admin: ${MACHINE_ID}"

    # Create sshuser with UID 2026
    if id sshuser &>/dev/null; then
        info "User 'sshuser' already exists — skipping creation."
    else
        info "Creating user: sshuser (UID 2026)"
        run useradd sshuser -m -U -s /bin/bash
    fi

    info "Setting UID 2026 for sshuser"
    run usermod -u 2026 sshuser

    info "Setting password for sshuser (P@ssw0rd)"
    echo "sshuser:P@ssw0rd" | run chpasswd

    info "Adding sshuser to wheel group (sudo access)"
    run usermod -aG wheel sshuser

    # Sudoers
    local sudoers_src
    if [ "$role" = "hq-srv" ]; then
        sudoers_src="network_setup/headquarters/server/etc/sudoers"
    else
        sudoers_src="network_setup/branch/server/etc/sudoers"
    fi
    info "Deploying sudoers (NOPASSWD for sshuser)"
    run chmod 740 /etc/sudoers
    deploy "$sudoers_src" /etc/sudoers
    run chmod 440 /etc/sudoers

    # SSH hardening (port 2026, AllowUsers sshuser, MaxAuthTries 2, Banner)
    local ssh_src banner_src
    if [ "$role" = "hq-srv" ]; then
        ssh_src="network_setup/headquarters/server/etc/openssh/sshd_config"
        banner_src="network_setup/headquarters/server/etc/openssh/banner"
    else
        ssh_src="network_setup/branch/server/etc/openssh/sshd_config"
        banner_src="network_setup/branch/server/etc/openssh/banner"
    fi

    info "Deploying sshd_config (port 2026, AllowUsers sshuser, MaxAuthTries 2)"
    ensure_dir /etc/openssh
    deploy "$ssh_src"    /etc/openssh/sshd_config
    deploy "$banner_src" /etc/openssh/banner

    info "Restarting sshd"
    run systemctl restart sshd

    ok "${role^^} user and SSH configuration complete."
}

#  Create users on HQ-RTR / BR-RTR (net_admin, sudo NOPASSWD)
na_router() {
    local role="$1"   # "hq-rtr" or "br-rtr"
    info "network_admin: ${MACHINE_ID}"

    # Create net_admin
    if id net_admin &>/dev/null; then
        info "User 'net_admin' already exists — skipping creation."
    else
        info "Creating user: net_admin"
        run useradd net_admin -m -U -s /bin/bash
    fi

    info "Setting password for net_admin (P@ssw0rd)"
    echo "net_admin:P@ssw0rd" | run chpasswd

    info "Adding net_admin to wheel group"
    run usermod -aG wheel net_admin

    # Sudoers
    local sudoers_src
    if [ "$role" = "hq-rtr" ]; then
        sudoers_src="network_setup/headquarters/router/etc/sudoers"
    else
        sudoers_src="network_setup/branch/router/etc/sudoers"
    fi
    info "Deploying sudoers (NOPASSWD for net_admin)"
    run chmod 740 /etc/sudoers
    deploy "$sudoers_src" /etc/sudoers
    run chmod 440 /etc/sudoers

    ok "${role^^} user configuration complete."
}

#  Dispatch: network_admin
run_network_admin() {
    info "--- Module: network_admin ---"
    local role="${VMID_ROLE[$MACHINE_ID]}"
    case "$role" in
        hq-srv) na_server "hq-srv" ;;
        br-srv) na_server "br-srv" ;;
        hq-rtr) na_router "hq-rtr" ;;
        br-rtr) na_router "br-rtr" ;;
        isp)    warn "No network_admin tasks defined for ISP." ;;
        hq-cli) warn "No network_admin tasks defined for HQ-CLI." ;;
    esac
}

#  Main
main() {
    # No arguments - show help
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    parse_args "$@"
    validate_args

    # Initialise run log
    : > /tmp/alphasys_run.log

    local role="${VMID_ROLE[$MACHINE_ID]}"
    local hostname="${VMID_HOSTNAME[$MACHINE_ID]}"

    sep
    _p "  alphasys starting"
    _p "  Machine ID : ${MACHINE_ID}  (${role}  /  ${hostname})"
    _p "  Module     : ${MODULE}"
    sep

    case "$MODULE" in
        network_setup)
            run_network_setup
            ;;
        network_admin)
            run_network_admin
            ;;
        hybrid)
            run_network_setup
            run_network_admin
            ;;
    esac

    sep

    if $HAD_ERROR; then
        _p "  Result: FAILED  (see /tmp/alphasys_run.log for details)"
        sep
        if ! $VERBOSE; then echo "alphasys: failed."; fi
        exit 1
    else
        _p "  Result: SUCCESS"
        sep
        if ! $VERBOSE; then echo "alphasys: success."; fi
        exit 0
    fi
}

main "$@"
