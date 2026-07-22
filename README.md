# NOMMA-ZABBIX

Minimal, high-signal Zabbix monitoring for K-12 IT infrastructure.

## Repository layout

```
Active Directory/
├── Agents/       — Zabbix Agent 2 UserParameter configuration
├── Docs/         — Deployment and validation guides
├── Scripts/      — PowerShell health-check helpers
└── Templates/    — Zabbix 7.2 YAML templates

papercut/
├── README.md           — Overview and quick start
├── setup.sh            — One-command deployment script
├── scripts/            — Health check scripts (bash)
├── agent/              — Zabbix Agent 2 config
├── templates/          — Zabbix 7.2 template YAML
└── docs/               — Deployment guide

Hyper-V/
├── scripts/            — PowerShell collector script
├── agent/              — Zabbix Agent 2 UserParameter config
├── templates/          — Zabbix template YAML
├── dashboards/         — Zabbix dashboard import YAML
├── tests/              — Test scripts and fixtures
└── docs/               — Troubleshooting guide
```

## Windows Active Directory

The first monitoring pack targets Windows Server 2022 Active Directory domain controllers using Zabbix 7.2 and Zabbix Agent 2.

### Templates

| Template | When to link it |
|----------|-----------------|
| `Windows Active Directory - Minimal` | Every DC now. Also link the official `Windows by Zabbix agent` template. |
| `Windows Active Directory - Replication` | Only after the domain has two or more DCs and normal replication has been verified. |

### Scope

The minimal template monitors AD DS, DNS, DFSR, Netlogon, KDC, Windows Time, SYSVOL/NETLOGON shares, local AD DNS resolution, LDAP/Kerberos TCP reachability, a narrow set of DFSR/DNS event IDs, and LDAP activity trends.

It deliberately does not alert on all event-log errors, user logons, or every NTDS counter.

### Deployment

See [`Active Directory/Docs/deployment.md`](Active%20Directory/Docs/deployment.md) and [`Active Directory/Docs/validation.md`](Active%20Directory/Docs/validation.md).

## PaperCut NG

Monitoring for PaperCut NG print server (Debian 12, internal H2 database) with Zabbix Agent 2.

**20 items, 18 triggers** covering: Application Server, database connection & pool, licensing, site servers, port health, disk usage, printer status (online/offline/toner/errors), and print activity.

### Quick start

1. **SSH into the PaperCut server** (`10.1.0.113`) and run:
   ```bash
   cd /tmp
   git clone https://github.com/l0cky12/NOMMA-ZABBIX.git
   cd NOMMA-ZABBIX/papercut
   sudo bash setup.sh
   ```
2. **Import the template** in Zabbix web UI (Configuration → Templates → Import → `papercut_template.yaml`)
3. **Link the template** to the "Papercut" host

See [`papercut/README.md`](papercut/README.md) and [`papercut/docs/deployment.md`](papercut/docs/deployment.md) for the full guide.

## Hyper-V

Hyper-V host monitoring for Windows Server with Zabbix Agent 2. Collects VM states, resource usage, and host health via PowerShell.

| File | Purpose |
|------|---------|
| `scripts/Get-ZabbixHyperV.ps1` | PowerShell collector — VM states, CPU, memory, host health |
| `agent/userparameter_hyperv.conf` | Zabbix Agent 2 UserParameter definitions |
| `templates/template_hyperv_standalone_replica_nomma.yaml` | Zabbix 7.2 template |
| `dashboards/dashboard_hyperv_fleet_nomma.yaml` | Fleet overview dashboard |
| `tests/` | Test fixtures and validation scripts |

See [`Hyper-V/README.md`](Hyper-V/README.md) for details.