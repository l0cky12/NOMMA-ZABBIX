# exacqVisionServer Monitoring — Deployment Guide

Monitor the exacqVisionServer service on the camera server (10.1.0.208) with
auto-restart logic and email escalation.

## Overview

| Component | Purpose |
|-----------|---------|
| `exacq_restart.ps1` | PowerShell script: waits 10 min, retries restart 3× |
| `userparameter_exacq.conf` | Zabbix Agent 2 config exposing status items |
| `template_exacqvision.yaml` | Zabbix 7.x template with items + triggers |
| This guide | Deployment steps |

### Flow

```
Camera Server (10.1.0.208)
  │
  ├─ exacqVisionServer service ───── Zabbix checks every 60s
  │                                    (native service.info key)
  │
  ├─ If STOPPED for 10 minutes ─────→ Trigger "DOWN" fires (HIGH)
  │                                    Action runs restart script
  │                                      │
  │                                      ├─ Try 1 ──→ SUCCESS? → auto-resolve
  │                                      ├─ Try 2 ──→ SUCCESS? → auto-resolve
  │                                      └─ Try 3 ──→ FAILED? → status = FAILED
  │                                                          ↓
  └─ exacq.restart.status = FAILED ──→ Trigger "restart FAILED" fires (DISASTER)
                                         Action sends EMAIL to admin
```

---

## Step 1: Deploy Zabbix Agent 2 (if not already installed)

Check if the agent is installed on 10.1.0.208:

```powershell
Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
```

If missing, use your existing Action1 script or the manual MSI approach:

```cmd
msiexec /i zabbix_agent2-7.4.12-windows-amd64-openssl.msi /qn ^
  SERVER=10.1.2.61 ^
  SERVERPORT=10051 ^
  HOSTNAME=CAMERA-SERVER ^
  TLSPSKIDENTITY=CAMERA-SERVER-PSK ^
  TLSACCEPT=psk ^
  TLSCONNECT=psk
```

> **Note**: Agent 2 requires Windows 10 / Server 2016+. Server 2016 is supported.

## Step 2: Deploy the Script

On the camera server (10.1.0.208), run as **Administrator**:

```powershell
# Create scripts directory
New-Item -ItemType Directory -Path "C:\Program Files\Zabbix Agent 2\scripts" -Force

# Copy the script (from network share or copy-paste)
# exacq_restart.ps1 → C:\Program Files\Zabbix Agent 2\scripts\exacq_restart.ps1

# Verify
Get-ChildItem "C:\Program Files\Zabbix Agent 2\scripts"
```

## Step 3: Deploy Agent Config

```powershell
# Copy userparameter_exacq.conf to:
# C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\userparameter_exacq.conf

# Verify
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\userparameter_exacq.conf"

# Restart agent
Restart-Service "Zabbix Agent 2"
```

## Step 4: Test Script (Manual First)

```powershell
# Run once to verify it works (dry run — service should be running)
& "C:\Program Files\Zabbix Agent 2\scripts\exacq_restart.ps1"

# Check the log
Get-Content "C:\ProgramData\Zabbix\exacqvision\exacq_restart.log"

# Verify Zabbix can read the UserParameter
zabbix_agent2 -t exacq.restart.status
```

## Step 5: Import Template into Zabbix

1. Open Zabbix frontend: https://zabbix.nomma.tech
2. Go to **Data collection → Templates**
3. Click **Import** (top-right)
4. Choose `template_exacqvision.yaml`
5. Leave defaults, click **Import**

### What the template provides

| Item key | Description | Interval |
|----------|-------------|----------|
| `service.info[exacqVisionServer,state]` | Native service state check | 60s |
| `exacq.restart.status` | Reads restart flag file | 60s |
| `exacq.uptime` | Server uptime | 300s |

| Trigger | Conditions | Severity |
|---------|-----------|----------|
| exacqVisionServer DOWN | Stopped for ≥10 consecutive minutes | HIGH |
| Restart FAILED | Status = FAILED | DISASTER |

## Step 6: Link Template to Host

1. Go to **Data collection → Hosts**
2. Find the camera server host (or create it if missing)
3. **Host name**: Match `HOSTNAME` from agent config
4. **Agent interfaces**: `10.1.0.208:10050`
5. **Templates**: Link `NOMMA ExacqVision by Zabbix Agent`
6. **Encryption**: Set PSK identity and key if using PSK
7. **Save**

## Step 7: Configure Zabbix Actions (Two Actions Needed)

### Action 1: Restart on DOWN

Trigger the restart script when service has been down 10+ minutes:

1. **Alerts → Actions → Trigger actions → Create action**
2. **Name**: "exacqVisionServer - Auto-Restart"
3. **Conditions**:
   - Trigger name = `exacqVisionServer DOWN — stopped for 10+ minutes`
4. **Operations → New**:
   - Operation type: **Remote command**
   - Target: **Current host**
   - Command:
     ```
     powershell -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent 2\scripts\exacq_restart.ps1"
     ```
5. **Save**

> **Windows Agent requirement**: Zabbix Agent config must allow remote commands.
> This is enabled by default in Zabbix Agent 2 (`EnableRemoteCommands=1`).

### Action 2: Email on FAILED

Send email when all 3 restart attempts fail:

1. **Alerts → Actions → Trigger actions → Create action**
2. **Name**: "exacqVisionServer - Restart Failed - Email Admin"
3. **Conditions**:
   - Trigger name = `exacqVisionServer restart FAILED — manual intervention required`
4. **Operations → New**:
   - Operation type: **Send message**
   - Send to: **Admin** (or your user group)
   - Subject: `DISASTER: exacqVisionServer restart failed on {HOST.NAME}`
   - Message:
     ```
     Trigger: {TRIGGER.NAME}
     Host: {HOST.NAME} ({HOST.IP})
     Severity: {TRIGGER.SEVERITY}
     Time: {EVENT.DATE} {EVENT.TIME}

     The exacqVisionServer restart script failed after 3 attempts.
     Manual intervention required.

     Check: RDP to {HOST.IP} and review:
       C:\ProgramData\Zabbix\exacqvision\exacq_restart.log
     ```
5. **Save**

## Step 8: Verify Everything

```powershell
# On the camera server — verify agent reports the items
zabbix_agent2 -t service.info[exacqVisionServer,state]
# Expected: service.info[exacqVisionServer,state] [s|0]

zabbix_agent2 -t exacq.restart.status
# Expected: exacq.restart.status [s|RUNNING]

# From the Zabbix server — remote check
zabbix_get -s 10.1.0.208 -k service.info[exacqVisionServer,state]
# Expected: 0
```

## Maintenance

### Log files

| Path | Size limit | Notes |
|------|-----------|-------|
| `C:\ProgramData\Zabbix\exacqvision\exacq_restart.log` | 1 MB (auto-rotates to .bak) | Full restart history |
| `C:\ProgramData\Zabbix\exacqvision\exacq_restart_status.txt` | ~10 bytes | Current status flag |
| `C:\ProgramData\Zabbix\exacqvision\exacq_restart_detail.txt` | ~200 bytes | Last attempt details |

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `exacq.restart.status` returns `NO_DATA` | Status file doesn't exist | Run script manually once |
| Service name wrong | Wrong service name on this server | Verify with `Get-Service -Name *exacq*` |
| Remote command not running | `EnableRemoteCommands=1` missing | Add to `zabbix_agent2.conf` and restart |
| Agent not reporting | PSK mismatch or firewall | Check Zabbix host encryption settings; verify TCP 10050 open to 10.1.2.61 |

## Files

```
exacqvision-monitoring/
├── Scripts/
│   └── exacq_restart.ps1          # Restart script for the server
├── Agents/
│   └── userparameter_exacq.conf   # Zabbix Agent 2 config
├── Templates/
│   └── template_exacqvision.yaml  # Zabbix 7.x template
└── Docs/
    └── deployment.md              # This file
```