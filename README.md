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
└── prompt.md     — Prompt for Hermes to build PaperCut NG monitoring
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

Monitoring for PaperCut NG print server, Print Deploy, and printer health. See [`papercut/prompt.md`](papercut/prompt.md) — paste that into the Hermes orchestrator to build the full setup.