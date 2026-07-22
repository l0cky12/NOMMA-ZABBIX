# PaperCut NG — Zabbix Monitoring Deployment Guide

This guide covers deploying PaperCut NG monitoring on **Debian 12 Bookworm** with **Zabbix Agent 2** and **PaperCut NG** (internal H2 database).

## Overview

| Component | What it does |
|-----------|-------------|
| `papercut_health.sh` | App server, DB, licensing, site servers, disk |
| `papercut_printers.sh` | Printer online/offline, toner, errors |
| `papercut_activity.sh` | Recent print job activity |
| `papercut.conf` | Zabbix Agent 2 UserParameter definitions |
| `papercut_template.yaml` | Zabbix template (import into Zabbix web UI) |
| `setup.sh` | One-command deployment script |

## What gets monitored

### Core Services
- PaperCut Application Server — **DISASTER** if stopped
- Database connection (internal H2) — **HIGH** if lost
- Database connection pool — **WARNING** at 80%, **HIGH** at 90%

### Network
- Port 9191 (HTTP) — **HIGH** if unreachable
- Port 9192 (HTTPS)
- Port 9195 (internal HTTPS)
- Port 9174 (Print Deploy)

### Licensing
- License validity — **HIGH** if invalid/expired
- License expiry — **WARNING** at ≤30 days, **HIGH** at ≤7 days

### Site Servers
- Offline site servers — **WARNING** if any are offline

### System Health
- Root disk usage — **WARNING** at >80%, **HIGH** at >90%
- Home disk usage — **WARNING** at >80%, **HIGH** at >90%

### Printer Health
- Offline printers — **WARNING** if any
- Low toner — **WARNING** if any
- Printer errors — **HIGH** if any

### Print Activity
- Minutes since last print job — **WARNING** at >60min, **HIGH** at >180min
- Jobs in last hour / 24 hours (trending data)

## Deployment

### Step 1: Copy files to the PaperCut server

SSH into your PaperCut server (`10.1.0.113`) and run:

```bash
# Pull files from the repo or copy them manually
# From the repo:
git clone https://github.com/l0cky12/NOMMA-ZABBIX.git /tmp/nomma-zabbix
cd /tmp/nomma-zabbix/papercut

# Or run the setup script
sudo bash setup.sh
```

### Step 2: Verify Zabbix Agent 2 is installed

```bash
zabbix_agent2 --version
```

If not installed:
```bash
sudo apt update && sudo apt install -y zabbix-agent2
```

### Step 3: Configure Zabbix Agent 2

Edit `/etc/zabbix/zabbix_agent2.conf`:

```ini
Server=10.1.2.61
ServerActive=10.1.2.61
Hostname=Papercut
```

Then restart:
```bash
sudo systemctl restart zabbix-agent2
sudo systemctl enable zabbix-agent2
```

### Step 4: Test the custom checks

```bash
sudo -u zabbix /usr/local/bin/papercut_health.sh appserver
sudo -u zabbix /usr/local/bin/papercut_health.sh db_connection
sudo -u zabbix /usr/local/bin/papercut_printers.sh total
sudo -u zabbix /usr/local/bin/papercut_activity.sh minutes_since
```

Each should return a number. If you get `UNKNOWN_CHECK` or errors, check:
- The scripts are executable (`ls -la /usr/local/bin/papercut_*.sh`)
- `server-command` exists at `/home/papercut/server/bin/linux/server-command`
- The `papercut` user can run the scripts

### Step 5: Test Zabbix Agent responds

```bash
zabbix_agent2 -t papercut.appserver.status
zabbix_agent2 -t papercut.db.connection
```

### Step 6: Import the template into Zabbix

1. Log into your Zabbix web UI (http://10.1.2.61/zabbix)
2. Go to **Configuration → Templates**
3. Click **Import** (top-right)
4. Choose `papercut_template.yaml`
5. Click **Import**

### Step 7: Link the template to the PaperCut host

1. Go to **Configuration → Hosts**
2. Click on the **Papercut** host
3. Go to the **Templates** tab
4. Click **Select** next to "Link new templates"
5. Search for `PaperCut NG by Zabbix Agent 2`
6. Select it and click **Add**
7. Click **Update**

### Step 8: Verify monitoring

1. Go to **Monitoring → Latest Data**
2. Filter by host: `Papercut`
3. You should see all 20+ items populating

## Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| Zabbix returns "Not supported" | Script not executable or wrong path |
| Script returns 0 for everything | `server-command` not found or PaperCut not running |
| `sudo -u zabbix` fails | Add zabbix to sudoers (see setup.sh) |
| Port checks show 0 | PaperCut bound to localhost only, not 0.0.0.0 |
| No printer data | Print Deploy not configured or no printers added |

## PaperCut API Reference

The scripts use the PaperCut `server-command` CLI tool:

```bash
/home/papercut/server/bin/linux/server-command health-check
/home/papercut/server/bin/linux/server-command get-system-status
/home/papercut/server/bin/linux/server-command list-printers
/home/papercut/server/bin/linux/server-command get-printer-details <printer>
/home/papercut/server/bin/linux/server-command get-license-info
/home/papercut/server/bin/linux/server-command list-site-servers
/home/papercut/server/bin/linux/server-command get-recent-print-jobs
```

## Files

| File | Destination on PaperCut server |
|------|--------------------------------|
| `scripts/papercut_health.sh` | `/usr/local/bin/papercut_health.sh` |
| `scripts/papercut_printers.sh` | `/usr/local/bin/papercut_printers.sh` |
| `scripts/papercut_activity.sh` | `/usr/local/bin/papercut_activity.sh` |
| `agent/papercut.conf` | `/etc/zabbix/zabbix_agent2.d/papercut.conf` |
| `templates/papercut_template.yaml` | Import into Zabbix web UI |