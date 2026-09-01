# SSL/TLS Certificate Monitoring - Deployment Guide

Certificate expiry monitoring for NOMMA's Linux and Windows servers, with a
severity ladder that starts three weeks before expiry and only sends email at
High and Disaster.

Zabbix server: `10.1.2.61` (https://zabbix.nomma.tech), Zabbix 7.4, Zabbix
Agent 2 on all target hosts.

## Overview

| Component | Purpose |
|-----------|---------|
| `templates/zabbix-ssl-certs.yaml` | Zabbix 7.4 template: endpoint LLD + Windows/Linux store LLD, four triggers per prototype |
| `scripts/win-cert-discovery.ps1` | Windows machine-store discovery and per-cert expiry (PowerShell 5.1 / Action1 safe) |
| `scripts/linux-cert-discovery.sh` | Linux file-scan discovery and per-file expiry (bash + openssl) |
| `agent/windows-ssl.conf` | Zabbix Agent 2 UserParameters for Windows |
| `agent/linux-ssl.conf` | Zabbix Agent 2 UserParameters for Linux |
| This guide | Deployment, Zabbix action setup, verification |

### How it fits together

```
Host in Zabbix
  |
  +-- {$TLS.ENDPOINTS} = papercut.nomma.tech:9192,dc01.nomma.lan:636
  |     |
  |     +-- "TLS endpoint discovery" (Script LLD, runs on the Zabbix server)
  |           splits the macro into one row per host:port
  |             |
  |             +-- web.certificate.get[host,port]   (Agent 2 built-in, master)
  |                   |
  |                   +-- days until expiry  --> 4 severity triggers
  |                   +-- expires on / subject / validation result
  |
  +-- "Windows certificate store discovery"   (enable on Windows hosts)
  |     win-cert-discovery.ps1 -Mode discover  ->  Cert:\LocalMachine\My only
  |       +-- tls.certs.win.expiry[thumbprint] --> 4 severity triggers
  |
  +-- "Linux certificate file discovery"      (enable on Linux hosts)
        linux-cert-discovery.sh discover "{$TLS.STORE.PATHS}"
          +-- tls.certs.linux.expiry[file,paths] --> 4 severity triggers
```

### Severity ladder

| Days remaining | Severity | Email |
|----------------|----------|-------|
| `<= {$TLS.WARN.DAYS}` (21) and `> 14` | WARNING | no, dashboard only |
| `<= {$TLS.AVERAGE.DAYS}` (14) and `> 7` | AVERAGE | no, dashboard only |
| `<= {$TLS.HIGH.DAYS}` (7) and `> 3` | HIGH | yes |
| `<= {$TLS.DISASTER.DAYS}` (3), including already expired | DISASTER | yes |

The bands do not overlap, so exactly one of the four is active at any time and
an escalating certificate walks up the ladder without leaving stale problems
behind. Trigger names carry the endpoint or CN plus the expiry date, for
example:

```
TLS papercut.nomma.tech:9192: certificate expires in 5 days, not after
Mar 10 12:00:00 2027 GMT (high at 7d)
```

---

## Step 1: Import the template

1. Open https://zabbix.nomma.tech
2. **Data collection -> Templates**
3. **Import** (top right)
4. Choose `templates/zabbix-ssl-certs.yaml`
5. Leave the defaults, click **Import**

This creates the template group `NOMMA/SSL-Certificates` and the template
`NOMMA SSL Certificates by Zabbix Agent 2`.

## Step 2: Endpoint monitoring (primary, no agent-side work)

This is the path that covers PaperCut, LDAPS and every other TLS listener.
It uses the Zabbix Agent 2 built-in key `web.certificate.get`, so there is
nothing to deploy on the host.

1. **Data collection -> Hosts -> `<host>` -> Templates**, link
   `NOMMA SSL Certificates by Zabbix Agent 2`
2. On the same host, **Macros -> Inherited and host macros**, set:

   | Macro | Value |
   |-------|-------|
   | `{$TLS.ENDPOINTS}` | `papercut.nomma.tech:9192,localhost:636` |

3. **Update**

Adding another server later is the same two actions: link the template, set
one macro. No template edits are needed.

Notes:

- Format is `host:port`, comma separated. A bare hostname defaults to port 443.
- Names may be either DNS zone, `nomma.lan` (AD) or `nomma.tech`
  (public facing). Use whichever name the certificate is actually issued for,
  because the validation result item reports on the name that was requested.
- Leave the macro empty on hosts that should not run endpoint checks. The
  discovery rule then returns an empty list and creates nothing.
- Certificates from the internal ADCS ("NOMMA Issuing CA 01") report
  `valid-but-self-signed` in the validation item unless the agent host trusts
  the issuing CA. Expiry monitoring is unaffected.

## Step 3: Windows certificate store scan (secondary)

Only needed on Windows hosts where you want the local machine store watched in
addition to the endpoint checks.

### 3a. Deploy the script and agent config

Run as **Administrator** on the target server (or push both files with
Action1 - the script is Action1 safe and needs no parameters for discovery):

```powershell
New-Item -ItemType Directory -Path "C:\Program Files\Zabbix Agent 2\scripts" -Force

# Copy win-cert-discovery.ps1 to:
#   C:\Program Files\Zabbix Agent 2\scripts\win-cert-discovery.ps1
# Copy windows-ssl.conf to:
#   C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\windows-ssl.conf

Get-ChildItem "C:\Program Files\Zabbix Agent 2\scripts"
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\windows-ssl.conf"

Restart-Service "Zabbix Agent 2"
```

### 3b. Enable the discovery rule for this host

The store-scan rules ship **disabled** so that linking the template to a mixed
Windows/Linux fleet does not create unsupported items on the wrong OS.

1. **Data collection -> Hosts -> `<host>` -> Discovery**
2. Open **Windows certificate store discovery**
3. Set **Enabled**, click **Update**

Leave **Linux certificate file discovery** disabled on Windows hosts.

## Step 4: Linux certificate file scan (secondary)

### 4a. Deploy the script and agent config

```bash
sudo install -o root -g root -m 0755 linux-cert-discovery.sh \
  /usr/local/bin/linux-cert-discovery.sh

sudo install -o root -g root -m 0644 linux-ssl.conf \
  /etc/zabbix/zabbix_agent2.d/linux-ssl.conf
```

Grant the agent the one command it needs, with `visudo`:

```
zabbix ALL=(root) NOPASSWD: /usr/local/bin/linux-cert-discovery.sh
```

Then:

```bash
sudo systemctl restart zabbix-agent2
```

### 4b. PKCS#12 keystore password (optional)

Only required if you want `.p12` / `.pfx` keystores scanned, such as PaperCut's
`/home/papercut/server/custom/papercut-tls.p12`. Create a root-guarded env
file:

```bash
sudo touch /etc/zabbix/tls_check.env
sudo chown root:root /etc/zabbix/tls_check.env
sudo chmod 0600 /etc/zabbix/tls_check.env
sudo nano /etc/zabbix/tls_check.env
```

Contents (one line, no password anywhere else):

```
TLS_P12_PASSWORD=<the keystore password>
```

The script parses this file with `grep`/`sed`; it never sources it, so nothing
in it can be executed. The password is handed to openssl through
`-passin env:` so it never appears in the process list.

If the file is absent, `.p12` and `.pfx` files are skipped silently. PaperCut's
certificate is still covered by the endpoint check on
`papercut.nomma.tech:9192`, so this file is genuinely optional.

### 4c. Set the scan paths and enable the discovery rule

1. **Data collection -> Hosts -> `<host>` -> Macros**, adjust
   `{$TLS.STORE.PATHS}` if the defaults do not fit. Default:

   ```
   /etc/pki,/etc/nginx,/etc/apache2,/etc/httpd,/etc/ssl/private,/home/papercut/server/custom
   ```

   `/etc/ssl/certs` (the system trust store) is always excluded by the script,
   so adding it has no effect.

2. **Data collection -> Hosts -> `<host>` -> Discovery**
3. Open **Linux certificate file discovery**, set **Enabled**, **Update**

Leave **Windows certificate store discovery** disabled on Linux hosts.

---

## Step 5: Email action (High and Disaster only)

One action, driven by the trigger tags the template sets. This uses the media
type and users that are **already configured** in Zabbix - do not create a new
media type.

1. **Alerts -> Actions -> Trigger actions -> Create action**
2. **Name**: `SSL certificate expiry - email on High and Disaster`
3. **Conditions** tab, **Add** each of these:

   | Type | Operator | Value |
   |------|----------|-------|
   | Trigger severity | is greater than or equals | `High` |
   | Value of tag | equals | tag `service`, value `tls-certificate` |

4. Set **Type of calculation** to **And/Or** (the default). Both conditions
   must match, so only High and Disaster certificate triggers fire this action.
5. **Operations** tab, **Operations -> Add**:
   - **Operation**: `Send message`
   - **Send to user groups**: the group that already receives Zabbix alerts
     (for example `Zabbix administrators`)
   - **Send to media type**: the existing email media type, or `- All -`
   - **Custom message**: on, with:

     Subject:
     ```
     {TRIGGER.SEVERITY}: certificate expiring on {HOST.NAME}
     ```

     Message:
     ```
     Trigger:  {TRIGGER.NAME}
     Host:     {HOST.NAME} ({HOST.IP})
     Severity: {TRIGGER.SEVERITY}
     Time:     {EVENT.DATE} {EVENT.TIME}
     Item:     {ITEM.NAME} = {ITEM.LASTVALUE}

     Renew through the internal ADCS ("NOMMA Issuing CA 01") and install the
     replacement on the host above.
     ```
6. **Recovery operations -> Add**: `Notify all involved` so the resolution is
   mailed once the new certificate is in place.
7. **Enabled**: on. **Add**.

WARNING and AVERAGE triggers deliberately do not match this action. They exist
only so the certificate shows up in **Monitoring -> Problems** three weeks
ahead.

---

## Step 6: Two-step verification

Always verify in this order: run the script as the account the agent uses, then
ask the agent for the item key. If step one works and step two does not, the
problem is the UserParameter or the agent restart, not the script.

### Linux

```bash
# 1. Run the script the way the agent runs it, as the zabbix user
sudo -u zabbix sudo -n /usr/local/bin/linux-cert-discovery.sh discover
# Expected: a JSON array, for example
# [{"{#TLS.CERT.FILE}":"/etc/pki/tls/certs/papercut.crt", ...}]

sudo -u zabbix sudo -n /usr/local/bin/linux-cert-discovery.sh \
  expiry /etc/pki/tls/certs/papercut.crt \
  "/etc/pki,/etc/nginx,/etc/apache2,/etc/httpd,/etc/ssl/private,/home/papercut/server/custom"
# Expected: a whole number of days, for example 214

# 2. Ask the agent for the same keys
zabbix_agent2 -t tls.certs.linux.discovery["/etc/pki,/etc/nginx,/etc/apache2,/etc/httpd,/etc/ssl/private,/home/papercut/server/custom"]
zabbix_agent2 -t web.certificate.get[papercut.nomma.tech,9192]
```

### Windows

```powershell
# 1. Run the script the way the agent runs it
& "C:\Program Files\Zabbix Agent 2\scripts\win-cert-discovery.ps1" -Mode discover
# Expected: a JSON array of machine certificates

& "C:\Program Files\Zabbix Agent 2\scripts\win-cert-discovery.ps1" `
  -Mode expiry -Thumbprint "<thumbprint from the JSON above>"
# Expected: a whole number of days

# 2. Ask the agent for the same keys
zabbix_agent2 -t tls.certs.win.discovery
zabbix_agent2 -t tls.certs.win.expiry[<thumbprint>]
zabbix_agent2 -t web.certificate.get[papercut.nomma.tech,9192]
```

### In the Zabbix frontend

1. **Monitoring -> Latest data**, filter by the host
2. Within one discovery interval (1 hour, or use **Execute now** on the
   discovery rule) you should see:
   - `TLS <endpoint>: days until certificate expiry`
   - `TLS <endpoint>: certificate expires on`
   - `TLS <endpoint>: certificate validation result`
   - one `days until expiry` item per discovered store certificate

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Endpoint discovery creates nothing | `{$TLS.ENDPOINTS}` empty or not set on the host | Set the macro at host level, then **Execute now** on the discovery rule |
| `web.certificate.get` unsupported | Passive-only agent, or Zabbix Agent 1 | The template uses active checks; set `ServerActive=10.1.2.61` and confirm Agent 2 is installed |
| `web.certificate.get` times out | Agent `Timeout` too low for the TLS handshake | Raise `Timeout` in `zabbix_agent2.conf` (default 3, maximum 30) and restart the agent |
| Store discovery unsupported on a Linux host | The Windows discovery rule is enabled there | Disable **Windows certificate store discovery** on that host, and the reverse on Windows hosts |
| `tls.certs.linux.discovery` returns `[]` | Nothing readable under `{$TLS.STORE.PATHS}`, or sudoers line missing | Run step 6 as the zabbix user; check `sudo -l -U zabbix` |
| `.p12` keystores never appear | `/etc/zabbix/tls_check.env` missing, unreadable, or wrong password | Create it as described in 4b; PaperCut is still covered by the endpoint check |
| `.p12` still not read with the correct password | OpenSSL 3.x refusing a legacy keystore | The script already retries with `-legacy`; if that fails the keystore uses an algorithm this OpenSSL build cannot open |
| Days item goes negative | The certificate has already expired | Expected. The DISASTER trigger stays active until the certificate is replaced |
| No email on High | Action conditions do not match | Check the trigger has tag `service: tls-certificate` and that the action severity condition is `>= High` |

## Files

| File | Destination |
|------|-------------|
| `templates/zabbix-ssl-certs.yaml` | Import into the Zabbix frontend |
| `scripts/win-cert-discovery.ps1` | `C:\Program Files\Zabbix Agent 2\scripts\win-cert-discovery.ps1` |
| `agent/windows-ssl.conf` | `C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\windows-ssl.conf` |
| `scripts/linux-cert-discovery.sh` | `/usr/local/bin/linux-cert-discovery.sh` (0755, root:root) |
| `agent/linux-ssl.conf` | `/etc/zabbix/zabbix_agent2.d/linux-ssl.conf` (0644, root:root) |
| PKCS#12 password (optional, created by hand) | `/etc/zabbix/tls_check.env` (0600, root:root) |

## Security notes

- Both scripts are read-only. They do not write files, change configuration,
  restart services or write to the registry.
- No credentials are stored in this repository. The only secret involved is the
  PKCS#12 keystore password, which lives solely in
  `/etc/zabbix/tls_check.env` (root-owned, `0600`) and is passed to openssl via
  `-passin env:` so it is not visible in `ps`.
- The Windows script reads `Cert:\LocalMachine\My` only. `CurrentUser` and all
  CA/Root stores are deliberately out of scope.
- The Linux script refuses any path outside `{$TLS.STORE.PATHS}`, refuses paths
  containing `..`, and always excludes `/etc/ssl/certs`, so the item key cannot
  be used to probe arbitrary files.
- The sudoers grant is limited to the single script path.
