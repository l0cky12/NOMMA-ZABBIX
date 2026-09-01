# NOMMA-ZABBIX

Minimal, high-signal Zabbix monitoring for K-12 IT infrastructure.

## Repository layout

```
Active Directory/
├── Agents/       - Zabbix Agent 2 UserParameter configuration
├── Docs/         - Deployment and validation guides
├── Scripts/      - PowerShell health-check helpers
└── Templates/    - Zabbix 7.2 YAML templates

papercut/
├── README.md           - Overview and quick start
├── setup.sh            - One-command deployment script
├── scripts/            - Health check scripts (bash)
├── agent/              - Zabbix Agent 2 config
├── templates/          - Zabbix 7.2 template YAML
└── docs/               - Deployment guide

Hyper-V/
├── scripts/            - PowerShell collector script
├── agent/              - Zabbix Agent 2 UserParameter config
├── templates/          - Zabbix template YAML
├── dashboards/         - Zabbix dashboard import YAML
├── tests/              - Test scripts and fixtures
└── docs/               - Troubleshooting guide

ExacqVision/
├── scripts/            - PowerShell service restart script
├── agent/              - Zabbix Agent 2 UserParameter config
├── templates/          - Zabbix 7.4 template YAML
└── docs/               - Deployment guide

SSL-Certificates/
├── scripts/            - Windows and Linux certificate discovery scripts
├── agent/              - Zabbix Agent 2 UserParameter configs (per OS)
├── templates/          - Zabbix 7.4 template YAML
└── docs/               - Deployment guide
```

## Service map

| Domain | Targets | Template | Docs |
|--------|---------|----------|------|
| Active Directory | Windows Server 2022 domain controllers | `Active Directory/Templates/` | [deployment](Active%20Directory/Docs/deployment.md) |
| PaperCut NG | Debian 12 print server (`10.1.0.113`) | `papercut/templates/papercut_template.yaml` | [deployment](papercut/docs/deployment.md) |
| Hyper-V | Windows Server Hyper-V hosts | `Hyper-V/templates/template_hyperv_standalone_replica_nomma.yaml` | [README](Hyper-V/README.md) |
| ExacqVision | Camera server (`10.1.0.208`) | `ExacqVision/templates/template_exacqvision.yaml` | [deployment](ExacqVision/docs/deployment.md) |
| SSL/TLS certificates | All Windows and Linux servers | `SSL-Certificates/templates/zabbix-ssl-certs.yaml` | [deployment guide](SSL-Certificates/docs/deployment-guide.md) |

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
| `scripts/Get-ZabbixHyperV.ps1` | PowerShell collector - VM states, CPU, memory, host health |
| `agent/userparameter_hyperv.conf` | Zabbix Agent 2 UserParameter definitions |
| `templates/template_hyperv_standalone_replica_nomma.yaml` | Zabbix 7.2 template |
| `dashboards/dashboard_hyperv_fleet_nomma.yaml` | Fleet overview dashboard |
| `tests/` | Test fixtures and validation scripts |

See [`Hyper-V/README.md`](Hyper-V/README.md) for details.

## SSL/TLS Certificates

Certificate expiry monitoring for every Windows and Linux server, on Zabbix 7.4
with Zabbix Agent 2. One template covers two discovery paths.

| File | Purpose |
|------|---------|
| `templates/zabbix-ssl-certs.yaml` | Zabbix 7.4 template: endpoint LLD, Windows store LLD, Linux file LLD |
| `scripts/win-cert-discovery.ps1` | Windows machine store discovery and per-cert expiry (PS 5.1 / Action1 safe) |
| `scripts/linux-cert-discovery.sh` | Linux PEM/PKCS#12 file discovery and per-file expiry (bash + openssl) |
| `agent/windows-ssl.conf` | UserParameters for `C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\` |
| `agent/linux-ssl.conf` | UserParameters for `/etc/zabbix/zabbix_agent2.d/` |

**Endpoint check (primary)** uses the Agent 2 built-in `web.certificate.get`
against the host macro `{$TLS.ENDPOINTS}`, a comma-separated list of
`host:port` endpoints. Adding a server is: link the template, set one macro.

**Store scan (secondary)** enumerates `Cert:\LocalMachine\My` on Windows and
PEM/PFX files under `{$TLS.STORE.PATHS}` on Linux. Both store-scan discovery
rules ship disabled; enable the one matching the host OS.

**Severity ladder**, four triggers per discovered certificate or endpoint:

| Days remaining | Severity | Email |
|----------------|----------|-------|
| 21 or fewer | WARNING | no |
| 14 or fewer | AVERAGE | no |
| 7 or fewer | HIGH | yes |
| 3 or fewer | DISASTER | yes |

See [`SSL-Certificates/docs/deployment-guide.md`](SSL-Certificates/docs/deployment-guide.md)
for deployment, the Zabbix email action steps, and verification.
