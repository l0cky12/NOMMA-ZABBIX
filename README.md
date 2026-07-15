# NOMMA-ZABBIX

Minimal, high-signal Zabbix monitoring for K-12 IT infrastructure.

## Windows Active Directory

The first monitoring pack targets Windows Server 2022 Active Directory domain controllers using Zabbix 7.2 and Zabbix Agent 2.

### Repository layout

- `templates/windows/active-directory/` — Zabbix 7.2 YAML templates.
- `scripts/windows/active-directory/` — PowerShell health-check helper.
- `agent/windows/active-directory/` — Zabbix Agent 2 UserParameter configuration.

### Templates

| Template | When to link it |
|---|---|
| `Windows Active Directory - Minimal` | Every DC now. Also link the official `Windows by Zabbix agent` template. |
| `Windows Active Directory - Replication` | Only after the domain has two or more DCs and normal replication has been verified. |

### Scope

The minimal template monitors AD DS, DNS, DFSR, Netlogon, KDC, Windows Time, SYSVOL/NETLOGON shares, local AD DNS resolution, LDAP/Kerberos TCP reachability, a narrow set of DFSR/DNS event IDs, and LDAP activity trends.

It deliberately does not alert on all event-log errors, user logons, or every NTDS counter.

## Deployment

See [`docs/windows/active-directory/deployment.md`](docs/windows/active-directory/deployment.md) and [`docs/windows/active-directory/validation.md`](docs/windows/active-directory/validation.md).
