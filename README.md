# Hearthglow Website — Hosting Administration Report

**Prepared for:** Matthew LaRocque, Owner — Hearthglow  
**Date:** June 2026  
**Hosting:** CanSpace Solutions — Medium Plan (3-year term)  
**Domain:** hearthglow.ca  
**Author:** Hearthglow AI System

---

## Executive Summary

Hearthglow's website runs on CanSpace's Medium shared hosting plan — a Canadian-owned, Canadian-server provider based in Quebec. The plan costs $9.99 CAD/month (locked for three years, no price increases), includes everything the site needs, and requires no third-party tools for email, SSL, or form handling. Everything is self-contained on the CanSpace server.

This document tells you exactly what you have, what each script does, what to do manually, and how to maintain the site going forward. If you follow the go-live checklist at the end of this document, the site will be fully operational with no recurring setup work required.

**Total site stack cost: $9.99 CAD/month.** No Formspree, no Cloudflare account, no GitHub Pages, no external services — CanSpace handles everything.

---

## Section 1 — What CanSpace Medium Gives You

| Feature | What it means for Hearthglow |
|---------|-------------------------------|
| **50GB SSD storage** | The website is ~150KB. You have room for thousands of photos and files. |
| **Unlimited bandwidth** | No metering. Every page load, every form submission is free. |
| **Unlimited email accounts** | matt@, hello@, quotes@, noreply@ — all created and included. |
| **Unlimited MySQL databases** | Not needed now; available if you add a booking system in Season 2. |
| **Free Enhanced SSL (Let's Encrypt)** | HTTPS on hearthglow.ca and www.hearthglow.ca, auto-renewed. |
| **Nightly backups** | CanSpace backs up every file and database nightly, ~7 days retained. |
| **Cloudflare CDN (built-in)** | Pages load faster globally. DDoS protection included. |
| **cPanel control panel** | Web dashboard at hearthglow.ca:2083 — manage everything visually. |
| **SSH access** | Command-line access to your server for scripted deployment. |
| **PHP 8.x** | The contact form (contact.php) runs natively — no Formspree needed. |
| **Git** | Version-controlled deployments available (advanced, optional). |
| **Web Application Firewall** | CanSpace-managed, blocks common attacks automatically. |
| **100% Canadian servers** | Data stays in Canada. PIPEDA compliant. Beauharnois, QC datacenter. |
| **Price-lock guarantee** | $9.99/month for the full three years. No renewal shock. |
| **24/7 support (5-min response)** | Phone: 1-888-993-6822. Ticket: canspace.ca/clients/supporttickets.php |

**CanSpace nameservers** (point hearthglow.ca here after setup):  
`ns1.canspace.ca` and `ns2.canspace.ca`

**cPanel URL:** `https://[YOUR_SERVER].canspace.ca:2083`  
(Your server hostname is in your CanSpace welcome email.)

---

## Section 2 — Website Architecture

```
Visitor's browser
      │
      ▼
Cloudflare CDN (CanSpace built-in)
      │  DDoS protection, speed boost
      ▼
CanSpace server (Beauharnois, QC)
      │  Apache + PHP 8.x + mod_rewrite
      ├── .htaccess         HTTPS redirect, security headers, caching rules
      ├── index.html        The single-page website (your storefront)
      ├── contact.php       Quote form handler — validates, emails Matt, logs submission
      └── logs/quotes.log   Local record of every quote submitted
            │
            └── PHP mail() → matt@hearthglow.ca (via CanSpace mail server)
                           → Confirmation email → client's inbox
```

No JavaScript framework. No database. No CMS. No login panel. The entire website is two files: `index.html` and `contact.php`. This is intentional — less complexity means less that can break, and less maintenance.

---

## Section 3 — File Inventory

### Website files (deployed to CanSpace `public_html/`)

| File | Purpose |
|------|---------|
| `index.html` | The complete Hearthglow website — single page, all sections |
| `contact.php` | Quote form processor: validates, sends email, confirms to client, logs |
| `.htaccess` | Apache rules: HTTPS redirect, security headers, compression, caching |

### Scripts (run from your computer — NOT uploaded to server)

| Script | When to run | What it does |
|--------|-------------|--------------|
| `scripts/config.sh` | Never run directly — sourced by other scripts | Stores your server credentials. Fill in once. |
| `scripts/setup-ssh-key.sh` | **Once, before first deploy** | Creates SSH key pair, uploads public key to cPanel. Enables password-free deployment. |
| `scripts/deploy.sh` | **Every time you update the site** | rsync's all website files to the server. Verifies the site is live after upload. |
| `scripts/setup-email.sh` | **Once, after DNS propagates** | Creates matt@, hello@, quotes@, noreply@ via cPanel API. Sets up forwarding. |
| `scripts/setup-dns.sh` | **Once, after nameservers change** | Adds SPF, DMARC, CAA, www CNAME records. Verifies MX. |
| `scripts/setup-ssl.sh` | **Once, after DNS propagates** | Verifies SSL cert is live. Installs .htaccess HTTPS redirect on server. |
| `scripts/backup.sh` | **Before any major site change** | Triggers cPanel full backup, downloads it to your computer. |
| `scripts/health-check.sh` | **Any time, on-demand** | Checks DNS, HTTPS, SSL expiry, response time. Logs results. |

### Supporting files

| File | Purpose |
|------|---------|
| `.gitignore` | Prevents credentials and logs from being committed to GitHub |
| `SETUP.md` | Deprecated — superseded by this README |

---

## Section 4 — Automated vs. Manual: What Happens When

### Fully automated (zero ongoing effort required)

| What | How often | Who does it |
|------|-----------|-------------|
| SSL certificate renewal | Every ~90 days | CanSpace / Let's Encrypt auto-renews |
| Nightly server backup | Every night | CanSpace — ~7 days of backups retained |
| DDoS protection | Continuous | CanSpace WAF + Cloudflare |
| Email spam/virus filtering | Every email | CanSpace mail filters |
| PHP security patches | As released | CanSpace — managed hosting |
| DKIM/SPF authentication | Every sent email | CanSpace mail server — configured once |
| Server uptime monitoring | Continuous | CanSpace NOC — 24/7 staffed |
| Quote email delivery | On form submit | contact.php → PHP mail() → your inbox |
| Client confirmation email | On form submit | contact.php → confirmation to client |

### Script-assisted (one command when needed)

| Situation | Script to run | Time |
|-----------|---------------|------|
| You update the website | `bash scripts/deploy.sh` | 30 seconds |
| You want a manual backup | `bash scripts/backup.sh` | 2–5 minutes |
| Something looks wrong | `bash scripts/health-check.sh` | 10 seconds |
| DNS is acting up | `bash scripts/setup-dns.sh --check-only` | 5 seconds |

### Manual steps (required once, at setup)

See Section 5 for the numbered go-live checklist.

---

## Section 5 — Go-Live Checklist (Do This Once)

Complete these steps in order. Estimated total time: 45–60 minutes.

**Before you start:** Have your CanSpace welcome email open — it contains your server hostname, cPanel username, and initial password.

---

**Step 1 — Fill in config.sh** *(5 min)*

Open `scripts/config.sh` in any text editor. Replace all `[YOUR_*]` placeholders:

- `CPANEL_HOST` → the server hostname from your welcome email (e.g. `s142.canspace.ca`)
- `CPANEL_USER` → your cPanel username
- `CPANEL_TOKEN` → create this in cPanel: Security → Manage API Tokens → Create → name it `hearthglow-scripts`
- Also update `[YOUR_CPANEL_USERNAME]` in `.htaccess` (the PHP error log path)

---

**Step 2 — Point hearthglow.ca to CanSpace nameservers** *(5 min + 1–24h propagation)*

In your CanSpace client area (canspace.ca/clients):
- Domains → hearthglow.ca → Manage → Change Nameservers
- Set nameserver 1: `ns1.canspace.ca`
- Set nameserver 2: `ns2.canspace.ca`
- Save

DNS propagation takes 1–24 hours. You can proceed with Steps 3–4 while waiting.

---

**Step 3 — Set up SSH key** *(3 min)*

Open Terminal (Mac) or Git Bash (Windows) and run:
```bash
bash scripts/setup-ssh-key.sh
```
This creates a key pair and uploads the public key to cPanel. You'll only ever do this once.

---

**Step 4 — Deploy the website** *(2 min)*

```bash
bash scripts/deploy.sh
```
This uploads `index.html`, `contact.php`, and `.htaccess` to your server. Once DNS is propagated, the site is live.

---

**Step 5 — Set up email accounts** *(5 min, after DNS propagates)*

```bash
bash scripts/setup-email.sh
```
Creates matt@, hello@, quotes@, and noreply@hearthglow.ca. You'll be prompted for a password — use a strong one (12+ characters) and save it in your password manager.

**Then configure your email client:**
- Go to cPanel → Email Accounts → matt@hearthglow.ca → Connect Devices
- CanSpace provides exact server settings for Apple Mail, Outlook, and iPhone

---

**Step 6 — Configure DNS records** *(3 min, after DNS propagates)*

```bash
bash scripts/setup-dns.sh
```
Adds SPF, DMARC, CAA, and www CNAME records. Protects email deliverability.

---

**Step 7 — Enable HTTPS** *(2 min, after DNS propagates)*

```bash
bash scripts/setup-ssl.sh
```
Verifies the SSL cert is active and installs the HTTPS redirect on the server.

---

**Step 8 — Run health check** *(1 min)*

```bash
bash scripts/health-check.sh
```
All green = site is live and healthy.

---

**Step 9 — Test the quote form** *(3 min)*

1. Go to `https://hearthglow.ca` → scroll to the quote form
2. Submit a test request with your own email
3. Confirm the email arrives at matt@hearthglow.ca with the formatted details
4. Confirm the confirmation email arrives at your test address

---

**Step 10 — Email client setup** *(5 min)*

Add matt@hearthglow.ca to your email client (Apple Mail, Outlook, Gmail app, iPhone):
- **Incoming:** `mail.hearthglow.ca` port `993` (IMAP SSL)
- **Outgoing:** `mail.hearthglow.ca` port `465` (SMTP SSL) or `587` (STARTTLS)
- **Username:** full email address — `matt@hearthglow.ca`
- **Password:** the password set in Step 5
- **Webmail (backup):** `https://hearthglow.ca/webmail`

---

## Section 6 — Updating the Website

Every time you want to change something on the site (update prices, add photos, change copy), the process is:

1. Open `D:\Hearthglow\Hearthglow\Website\index.html` in any text editor (or Notepad)
2. Make your changes and save
3. Open Terminal / Git Bash
4. Run: `bash scripts/deploy.sh`

The script uploads only the changed files and verifies the site is live. Takes about 30 seconds.

### Common updates

**Add pricing after Nicole's confirmation:**
Search `index.html` for: `Pricing varies by property size.`
Replace with: `Starting at $[PRICE]. Request a quote for your home.`
(Do this for each of the three tier cards.)

**Update contact email:**
Search `index.html` for: `matt@hearthglow.ca`
Replace all instances with the new address if it changes.

---

## Section 7 — Email Administration

### Accounts created by setup-email.sh

| Account | Purpose | Notes |
|---------|---------|-------|
| `matt@hearthglow.ca` | Primary — all client communication | Configure in your email client |
| `hello@hearthglow.ca` | Public-facing contact (shown on website) | Forwards to matt@ |
| `quotes@hearthglow.ca` | Quote request funnel alias | Forwards to matt@ |
| `noreply@hearthglow.ca` | PHP form sender | Used by contact.php |

### Managing email via cPanel

- **Create new account:** cPanel → Email Accounts → Create
- **Change password:** cPanel → Email Accounts → Manage → Update Password
- **Spam settings:** cPanel → SpamAssassin → Configure
- **Webmail:** https://hearthglow.ca/webmail (works anywhere, any device)

### Email client settings

| Setting | Value |
|---------|-------|
| Incoming server | mail.hearthglow.ca |
| IMAP port | 993 (SSL/TLS) |
| POP3 port | 995 (SSL/TLS) |
| Outgoing server | mail.hearthglow.ca |
| SMTP port | 465 (SSL/TLS) or 587 (STARTTLS) |
| Username | Full email address |

---

## Section 8 — Backup and Recovery

### What CanSpace backs up automatically
Every account is backed up nightly. Approximately 7 days of backups are retained. This covers: all website files, databases, and email accounts.

### How to restore (if something goes wrong)
1. Log into cPanel: https://[YOUR_SERVER].canspace.ca:2083
2. Backup Wizard → Restore → Full Backup
3. Select the backup date and restore

### On-demand backup before major changes
```bash
bash scripts/backup.sh
```
Downloads a full backup to `Website/backups/` on your local computer. The last 5 backups are kept; older ones are pruned automatically.

---

## Section 9 — Maintenance Calendar

| When | Action | Time |
|------|--------|------|
| **Before any site update** | `bash scripts/backup.sh` | 5 min |
| **After any site update** | `bash scripts/deploy.sh` | 1 min |
| **Monthly** | `bash scripts/health-check.sh` | 1 min |
| **When pricing is confirmed (Nicole)** | Update tier cards in index.html, redeploy | 10 min |
| **September 2026** | Add GBP review link to contact.php confirmation email | 10 min |
| **Annually** | Review CanSpace account, confirm auto-renewal settings | 10 min |
| **3-year mark (2029)** | Renew hosting (or CanSpace auto-renews — confirm billing settings) | — |

**Things you never need to do:**
- Renew SSL certificate (auto-renewed by CanSpace)
- Patch PHP or Apache (managed by CanSpace)
- Monitor for DDoS (CanSpace WAF handles it)
- Pay for Formspree or any form service (contact.php handles it natively)

---

## Section 10 — Costs

| Item | Cost | Period |
|------|------|--------|
| CanSpace Medium hosting | $9.99 CAD/month | 3-year lock |
| hearthglow.ca domain | ~$15–20 CAD/year | Annual renewal |
| SSL certificate | $0 | Included |
| Email hosting | $0 | Included |
| Quote form processing | $0 | Runs on hosting (no Formspree) |
| Backups | $0 | Included |
| CDN + DDoS protection | $0 | Cloudflare included |
| **Total** | **~$11.25–11.67 CAD/month** | — |

**Comparison to Jobber:** $174 CAD/month → replaced by $11.25 CAD/month for the website layer. The full Hearthglow system (website + CX automation) runs at approximately $11–12 CAD/month vs. $174/month previously.

---

## Section 11 — Support and Troubleshooting

### CanSpace support
- **Phone:** 1-888-993-6822 (24/7, typically answered in under 5 minutes)
- **Ticket:** canspace.ca/clients/supporttickets.php
- **Live chat:** canspace.ca (chat widget)

### Quick diagnostics
```bash
# Is everything working?
bash scripts/health-check.sh

# Is DNS propagated?
bash scripts/setup-dns.sh --check-only

# What HTTP code is the site returning?
curl -s -o /dev/null -w "%{http_code}" https://hearthglow.ca/
```

### Common issues and solutions

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| Site not loading | DNS not propagated | Wait up to 24h after nameserver change |
| HTTPS not working | SSL not provisioned yet | Wait for DNS; re-run setup-ssl.sh |
| Quote form not sending email | PHP mail or SPF issue | Check cPanel → Email Deliverability; call CanSpace |
| Email going to spam | DKIM not enabled | cPanel → Email Deliverability → Fix |
| SSH connection refused | SSH key not authorized | Re-run setup-ssh-key.sh; authorize key in cPanel |
| 500 error on contact form | PHP syntax or permissions | Check logs/ on server; call CanSpace |

---

## Appendix — Script Reference

### config.sh
Central credential file. Sourced by every other script. Fill in once and leave it. Never put this file in a public GitHub repository.

### setup-ssh-key.sh
Generates an Ed25519 SSH key pair and uploads the public key to cPanel via UAPI. After this runs, all deployment and backup scripts connect without a password.

### deploy.sh
Uses rsync over SSH to push website files to `public_html/`. Excludes scripts, logs, and markdown files. Verifies the site returns HTTP 200 after upload. Logs each deployment to `logs/deploy.log`.

### setup-email.sh
Creates four email accounts via the cPanel UAPI (Email.add_pop). Sets up forwarding rules for hello@ and quotes@ to route to matt@. Outputs IMAP/SMTP settings at the end.

### setup-dns.sh
Checks and adds DNS records: SPF (email authentication), DMARC (email policy), CAA (SSL issuer restriction), www CNAME. All changes made via cPanel ZoneEdit UAPI. Run with `--check-only` to audit without changing anything.

### setup-ssl.sh
Reads the SSL certificate and confirms it's valid and not expiring soon. Pushes `.htaccess` to the server via SSH to enforce HTTPS redirect and set security headers (HSTS, X-Frame-Options, CSP, etc.).

### backup.sh
Triggers a cPanel full backup via UAPI (Backup.fullbackup_to_homedir), waits for completion, then downloads the `.tar.gz` to `Website/backups/` via SCP. Keeps the 5 most recent local copies. Logs each backup to `backups/backup.log`.

### health-check.sh
Runs a battery of checks: A/MX/SPF/DMARC DNS records, HTTP→HTTPS redirect, HTTPS response, SSL cert expiry, page response time, disk usage. Produces a pass/warn/fail summary. Logs to `logs/health.log`.

---

*Hearthglow Website Administration Report | June 2026 | Confidential*
