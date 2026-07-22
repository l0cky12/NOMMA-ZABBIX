# PaperCut NG — Zabbix Monitoring

Complete monitoring setup for PaperCut NG on Debian 12 Bookworm with Zabbix Agent 2.

## Files

```
papercut/
├── setup.sh                          ← One-command deployment script (run on PaperCut server)
├── prompt.md                         ← Original build prompt (reference)
├── scripts/
│   ├── papercut_health.sh            ← App server, DB, licensing, site servers, disk checks
│   ├── papercut_printers.sh          ← Printer online/offline, toner, error checks
│   └── papercut_activity.sh          ← Recent print job activity monitoring
├── agent/
│   └── papercut.conf                 ← Zabbix Agent 2 UserParameter definitions
├── templates/
│   └── papercut_template.yaml        ← Zabbix 7.2 template (import via web UI)
└── docs/
    └── deployment.md                 ← Full deployment guide
```

## What it monitors

| Category | Checks | Alert thresholds |
|----------|--------|-----------------|
| **App Server** | PaperCut Application Server process | DISASTER if stopped |
| **Database** | Connection status, pool utilisation | WARNING >80%, HIGH >90% |
| **Network** | Ports 9191, 9192, 9195, 9174 | HIGH if unreachable |
| **Licensing** | License validity, expiry days | WARNING ≤30d, HIGH ≤7d |
| **Site Servers** | Offline site servers | WARNING if any |
| **Disk** | Root, /home usage | WARNING >80%, HIGH >90% |
| **Printers** | Online/offline, toner, errors | WARNING/HIGH per category |
| **Activity** | Minutes since last job, jobs/hr, jobs/day | WARNING >60min, HIGH >180min |

**Total: 20 items, 18 triggers** — all with warning-before-critical thresholds.

## Environment

| Setting | Value |
|---------|-------|
| PaperCut server | 10.1.0.113 |
| Zabbix server | 10.1.2.61 |
| OS | Debian 12 Bookworm |
| Database | Internal (H2) |
| Agent | Zabbix Agent 2 |

## Quick start

1. **SSH into PaperCut server** and run:
   ```bash
   sudo bash setup.sh
   ```
2. **Import the template** in Zabbix web UI (Configuration → Templates → Import)
3. **Link the template** to the "Papercut" host

See [`docs/deployment.md`](docs/deployment.md) for the full guide.