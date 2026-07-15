# Deploying Windows Active Directory monitoring

## Prerequisites

- Zabbix Server 7.2 at `10.1.2.98`.
- Domain controller `DC2023` at `10.1.0.115`.
- Zabbix Agent 2 installed on the DC.
- TCP 10050 allowed **to the DC only from `10.1.2.98`** for passive checks.
- TCP 10051 allowed from the DC to Zabbix Server for active checks.

## Agent configuration

Set these values in `C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf`:

```ini
Server=10.1.2.98
ServerActive=10.1.2.98
Hostname=DC2023
Timeout=15

TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=DC2023-PSK
TLSPSKFile=C:\Program Files\Zabbix Agent 2\zabbix_agent2.psk
```

Generate a 32-byte PSK in elevated PowerShell:

```powershell
$pskPath = 'C:\Program Files\Zabbix Agent 2\zabbix_agent2.psk'
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
[Convert]::ToHexString($bytes) | Set-Content -Path $pskPath -Encoding ascii -NoNewline
Get-Content $pskPath
```

In the Zabbix host encryption settings, select PSK for inbound and outbound connections, use identity `DC2023-PSK`, and paste the generated PSK.

Copy the repository files as documented at the top of `agent/windows/active-directory/zabbix_agent2.d/active-directory.conf`, then restart the agent:

```powershell
Restart-Service 'Zabbix Agent 2'
```

## Zabbix host setup

1. Create host `DC2023` in host group `Domain Controllers`.
2. Set its Agent interface to `10.1.0.115:10050`.
3. Add host tags: `role:domain-controller`, `service:active-directory`, `site:primary`.
4. Link both `Windows by Zabbix agent` and `Windows Active Directory - Minimal`.
5. Import and link `Windows Active Directory - Replication` only after DC #2 is operational and `repadmin /replsummary` is clean.

## Alert hygiene

- Make each custom service trigger dependent on the official template's agent-unavailable trigger after importing.
- Notify by email for Warning, High, and Disaster in the `Domain Controllers` group.
- Schedule maintenance before patching or restarting a DC.
- Do not enable broad Windows error-log alerts.
