---
name: linux-administration
description: Linux system administration — performance tuning, disk management, networking, systemd services, log analysis, user management, and troubleshooting system issues
---

## Linux Administration

### 1. System Overview

```bash
# Quick health check
uname -a                    # Kernel version
cat /etc/os-release         # OS distribution
uptime                      # Load average
free -h                     # Memory usage
df -h                       # Disk usage
lscpu                       # CPU info
```

### 2. Performance Diagnostics

```bash
# CPU
top -b -n 1 -o %CPU | head -20     # Top CPU consumers
mpstat -P ALL 1 3                    # Per-core CPU stats
pidstat -u 1 5                       # Per-process CPU

# Memory
free -h
vmstat 1 5
cat /proc/meminfo | head -10
slabtop -s c -o | head -20          # Kernel slab cache

# Disk I/O
iostat -xz 1 5                      # Per-device I/O stats
iotop -b -n 3                       # Per-process I/O
lsblk                               # Block devices

# Network
ss -tuln                             # Listening ports
ss -s                                # Socket summary
ip -s link                           # Interface stats
sar -n DEV 1 5                       # Network throughput
```

### 3. Log Analysis

```bash
# System logs
journalctl -p err --since "1 hour ago"       # Recent errors
journalctl -u <service> --since today        # Service logs
dmesg -T | tail -50                          # Kernel messages

# Common log locations
/var/log/messages      # General system (RHEL/Amazon Linux)
/var/log/syslog        # General system (Debian/Ubuntu)
/var/log/auth.log      # Authentication
/var/log/cloud-init.log # EC2 cloud-init
/var/log/secure        # Security events (RHEL)
```

### 4. Service Management

```bash
# systemd
systemctl status <service>
systemctl list-units --failed
systemctl list-timers --all

# Process management
ps auxf                              # Process tree
pgrep -la <name>                     # Find processes
strace -p <pid> -c                   # System call summary
```

### 5. Disk Management

```bash
# Find large files
du -sh /* 2>/dev/null | sort -rh | head -10
find / -xdev -type f -size +100M 2>/dev/null

# Check for inode exhaustion
df -i

# LVM management
pvs && vgs && lvs
```

### 6. Network Diagnostics

```bash
# Connectivity
ping -c 3 <host>
traceroute <host>
mtr -r -c 10 <host>

# DNS
dig <domain>
dig <domain> +trace
cat /etc/resolv.conf

# Firewall
iptables -L -n -v
nft list ruleset
```

### 7. User & Permission

```bash
# Users
cat /etc/passwd | grep -v nologin
last -10                             # Recent logins
who                                  # Current sessions

# Permissions
ls -la <path>
getfacl <path>
find /path -perm -o+w -type f       # World-writable files
```
