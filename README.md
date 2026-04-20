# alphasys

**Automated network deployment utility for the federal demoexam**
Specialty: **09.02.06 — Network & System Administration**
Platform: Proxmox VMs running ALT Server 11.0 / ALT Workstation 11.1 (x86_64)

---

## Overview

`alphasys` automates the full initial configuration of every virtual machine
in the exam topology. Instead of running dozens of commands by hand on each
node, you run a single command and the script deploys the correct network
interfaces, routing, services, firewall rules, users and SSH settings for
that specific machine.

All configuration files (interface settings, FRR configs, BIND zone files,
DHCP config, sshd_config, sudoers, etc.) are stored as ready-to-deploy
resources inside the `resources/` directory and are copied directly to their
target paths on the system.

---

## Network Topology

| VMID | Device | Role                        |
|------|--------|-----------------------------|
| 100  | ISP    | Internet provider / NAT     |
| 101  | HQ-RTR | HQ router (VLAN, GRE, OSPF, DHCP) |
| 102  | BR-RTR | Branch router (GRE, OSPF)   |
| 103  | HQ-SRV | HQ server (DNS/BIND, SSH)   |
| 104  | BR-SRV | Branch server (SSH)         |
| 105  | HQ-CLI | HQ client (DHCP)            |

### Addressing

| Device | Interface   | IP Address     | Mask | VLAN |
|--------|-------------|----------------|------|------|
| ISP    | ens19       | DHCP           | DHCP | —    |
|        | ens20       | 172.16.1.1     | /28  | —    |
|        | ens21       | 172.16.2.1     | /28  | —    |
| HQ-RTR | ens19       | 172.16.1.2     | /28  | —    |
|        | ens20.100   | 192.168.10.1   | /27  | 100  |
|        | ens20.200   | 192.168.20.1   | /28  | 200  |
|        | tun1 (GRE)  | 10.10.10.1     | /30  | —    |
| BR-RTR | ens19       | 172.16.2.2     | /28  | —    |
|        | ens20       | 192.168.30.1   | /28  | —    |
|        | tun1 (GRE)  | 10.10.10.2     | /30  | —    |
| HQ-SRV | ens19       | 192.168.10.2   | /27  | 100  |
| BR-SRV | ens19       | 192.168.30.2   | /28  | —    |
| HQ-CLI | ens19       | DHCP           | /28  | 200  |

---

## Project Structure

```
alphasys/
├── bin/
│   └── alphasys          # Main executable script
├── resources/
│   └── network_setup/
│       ├── isp/          # ISP config files
│       ├── headquarters/
│       │   ├── router/   # HQ-RTR config files
│       │   └── server/   # HQ-SRV config files
│       └── branch/
│           ├── router/   # BR-RTR config files
│           └── server/   # BR-SRV config files
├── install.sh            # Installer
└── README.md
```

---

## Installation

Copy the project to the target machine and run the installer as root:

```bash
chmod +x install.sh
bash install.sh
```

The installer:
1. Copies the project to `/root/alphasys/`
2. Creates a symlink `/usr/local/bin/alphasys → /root/alphasys/bin/alphasys`

After installation `alphasys` is available as a global command.

---

## Usage

```
alphasys --vmid=<id> -mod=<module> [--output]
```

### Options

| Flag | Description |
|------|-------------|
| `--vmid=<id>` | Proxmox VMID of the target machine (required with `-mod`) |
| `-mod=<module>` | Module to run: `network_setup`, `network_admin`, `hybrid` |
| `-o, --output` | Verbose output — prints every action and command response with timestamps |
| `-h, --help` | Show help message |

### Examples

```bash
# Configure HQ-RTR network from scratch
alphasys --vmid=101 -mod=network_setup --output

# Configure HQ-SRV network from scratch
alphasys --vmid=103 -mod=network_setup --output

# Silent mode (result only)
alphasys --vmid=104 -mod=network_setup
```

---

## Modules

### ✅ network_setup — fully implemented

Performs the complete initial configuration of a machine based on its VMID.

| VMID | What gets configured |
|------|----------------------|
| 100 (ISP)    | Hostname, ens20/ens21 static IPs, IP forwarding, firewalld + masquerade (SNAT/PAT) |
| 101 (HQ-RTR) | Hostname, ens19/ens20/VLANs/tun1, IP forwarding, firewalld, GRE tunnel, OSPF (frr), DHCP server (dhcpd), user `net_admin` |
| 102 (BR-RTR) | Hostname, ens19/ens20/tun1, IP forwarding, firewalld, GRE tunnel, OSPF (frr), user `net_admin` |
| 103 (HQ-SRV) | Hostname, ens19, DNS server (bind) with forward + reverse zones, sshd hardening (port 2026), user `sshuser` |
| 104 (BR-SRV) | Hostname, ens19, sshd hardening (port 2026), user `sshuser` |
| 105 (HQ-CLI) | Hostname (DHCP configured manually via GUI) |

### 🚧 network_admin — in development

Planned: additional user and access management tasks beyond initial setup.

### 🚧 hybrid — in development

Planned: combined operation mode running multiple configuration stages.

---

## Output & Logging

All command output is always written to `/root/alphasys_result.log`.

With `--output`, every action is printed to the console in real time:

```
[14:22:01 UTC+3] [INFO]  network_setup: 101
[14:22:01 UTC+3] >> hostnamectl set-hostname hq-rtr.au-team.irpo
[14:22:01 UTC+3]     (command output lines...)
[14:22:04 UTC+3] [INFO]  Installing firewalld
[14:22:04 UTC+3] >> apt-get install -y firewalld
[14:22:04 UTC+3]     Reading package lists...
[14:22:06 UTC+3] [ERROR] Command failed: ...   ← errors highlighted in red
```

Without `--output` (silent mode), only the final result is printed:

```
alphasys: success.
alphasys: failed.
```

---

## Credentials

| User | Password | UID | Where |
|------|----------|-----|-------|
| `root` | `P@ssw0rd` | — | All VMs |
| `net_admin` | `P@ssw0rd` | — | HQ-RTR, BR-RTR |
| `sshuser` | `P@ssw0rd` | 2026 | HQ-SRV, BR-SRV |

SSH on HQ-SRV and BR-SRV: port **2026**, only `sshuser` is allowed.
