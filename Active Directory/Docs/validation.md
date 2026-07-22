# Validation and safe alert testing

## Before importing

Run these checks from the Zabbix Server:

```bash
zabbix_get -s 10.1.0.115 -k agent.ping
zabbix_get -s 10.1.0.115 -k ad.sysvol_netlogon.shares
zabbix_get -s 10.1.0.115 -k ad.dns.srv_lookup
```

Expected output is `1`, `0`, and `0`, respectively.

Run these checks on `DC2023`:

```powershell
Get-SmbShare SYSVOL,NETLOGON
$domain = (Get-CimInstance Win32_ComputerSystem).Domain
Resolve-DnsName "_ldap._tcp.dc._msdcs.$domain" -Type SRV -Server 127.0.0.1
```

## Safe alert tests

| Test | Expected result | Restore |
|---|---|---|
| Stop Zabbix Agent 2 | Agent-unavailable problem after approximately five minutes. | `Start-Service 'Zabbix Agent 2'` |
| Temporarily block TCP 389 from `10.1.2.98` | LDAP TCP availability problem. | Remove the test firewall rule. |
| Stop DNS Server during an approved maintenance window | DNS service and local AD DNS lookup problems. | `Start-Service DNS` |

Do **not** stop AD DS (`NTDS`) on a sole DC merely to test monitoring.

## After a second DC is added

Before linking the replication template to either DC, run:

```powershell
repadmin /replsummary
repadmin /showrepl
```

Only enable the template if the normal replication baseline is clean. Then validate both Zabbix items:

```bash
zabbix_get -s <dc-ip> -k ad.replication.failures
zabbix_get -s <dc-ip> -k ad.replication.oldest_age
```

A healthy result is `0` replication failures. The age is the seconds since the oldest successful inbound replication; it should remain well below the 30-minute warning threshold in normal operation.
