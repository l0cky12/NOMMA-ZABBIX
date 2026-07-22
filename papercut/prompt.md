# PaperCut NG — Zabbix Monitoring Setup

## Prompt for Hermes Orchestrator

Paste this into the Hermes orchestrator chat to build the full monitoring setup:

---

> Set up Zabbix monitoring for PaperCut NG on my infrastructure. I need proactive monitoring — warnings before things break, not after.
>
> **Environment:**
> - PaperCut NG server: `10.1.0.113`
> - Zabbix server: *[your Zabbix server IP/hostname]*
> - Print Deploy public key: `mYOSHLEccGJQCe5VD/71SAA/SV4HFg6BfIPP45lj+Cs=`
>
> **What I need monitored (with warning thresholds):**
>
> **1. Core Services** — monitor that these are running and alert if stopped:
> - PaperCut Application Server
> - PaperCut Print Provider
> - CUPS printing service
> - Database service (PostgreSQL/MariaDB — confirm which)
>
> **2. Port Health** — TCP connectivity checks, warn before total failure:
> - 9191 (PaperCut HTTP)
> - 9192 (PaperCut HTTPS)
> - 9195 (PaperCut internal HTTPS)
> - 9174 (Print Deploy)
>
> **3. Application Health** — via PaperCut API or log scraping:
> - Application Server status (alive/running)
> - Database connection — check and warn before failure
> - Database connection pool utilization — alert at 80%, critical at 90%
> - Invalid licensing — detect and alert
> - Offline Site Servers — detect and alert
>
> **4. System Health** — on the PaperCut server:
> - Low disk space — warn at <20% free, critical at <10%
> - Recent print activity — warn if no jobs in last 1 hour (stale queue)
>
> **5. Printer Health** — per printer:
> - Printer online/offline state
> - Out of toner / low toner warnings
> - Printer errors
> - Recent job submission check
>
> **Deliverables:**
> - Zabbix template XML (or however Zabbix does it) with all items, triggers, and discovery rules
> - Host configuration steps
> - Any scripts needed on the PaperCut server (e.g., PaperCut API calls via `server-command`, or custom checks)
> - Trigger thresholds set to WARNING first, then CRITICAL — no surprises
> - Delivery method: write files to a local directory, or apply directly to Zabbix if API access is available
>
> **Don't start yet — confirm what info you need and the plan first.**