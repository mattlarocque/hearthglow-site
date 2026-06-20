# Hearthglow Website — Setup Guide

Three things to do before the site is live: register the domain, activate the quote form, and deploy the site. Each step is about 10 minutes.

---

## Step 1 — Register hearthglow.ca

Use a CIRA-accredited Canadian registrar. Recommended option:

**Rebel.ca** (Canadian, straightforward, ~$16 CAD/year for .ca)
1. Go to rebel.ca → search "hearthglow.ca"
2. Add to cart and complete purchase
3. You'll get DNS management access from your Rebel dashboard

Alternative: **Namecheap** also works and has a clean interface.

> If hearthglow.ca is taken, try hearthglowlights.ca or hearthglow.ca alternatives.

---

## Step 2 — Activate the quote form (Formspree)

The form in `index.html` currently has a placeholder form action. You need to activate it with a free Formspree account.

1. Go to **formspree.io** → Sign up (free tier: 50 submissions/month — more than enough for Season 1)
2. Click **New Form** → name it "Hearthglow Quote Requests" → set notification email to matt@hearthglow.ca
3. Formspree gives you a form endpoint like: `https://formspree.io/f/xpzgkwvj`
4. Open `index.html` and find this line (around line 270):
   ```
   action="https://formspree.io/f/YOUR_FORM_ID"
   ```
5. Replace `YOUR_FORM_ID` with your actual ID (e.g., `xpzgkwvj`)
6. Save the file

From that point on, every quote request goes straight to matt@hearthglow.ca.

---

## Step 3 — Deploy to Cloudflare Pages (free, forever)

Cloudflare Pages hosts your site for free with no monthly cost.

### 3a — Create a GitHub repository

1. Go to **github.com** → Sign up or log in
2. Click **New repository** → name it `hearthglow-website` → set to Public → click Create
3. Upload `index.html` to the repository (drag-and-drop in the GitHub interface)

### 3b — Connect to Cloudflare Pages

1. Go to **pages.cloudflare.com** → sign up free
2. Click **Create a project** → Connect to Git → authorize GitHub
3. Select the `hearthglow-website` repository
4. Build settings:
   - **Framework preset:** None
   - **Build command:** (leave blank)
   - **Build output directory:** `/` (root)
5. Click Deploy

Your site will be live at a URL like `hearthglow-website.pages.dev` within 2 minutes.

---

## Step 4 — Connect your domain

1. In your Cloudflare Pages project → Settings → Custom Domains → Add custom domain
2. Enter `hearthglow.ca` → click Continue
3. Cloudflare will tell you the DNS records to add
4. Log into your Rebel (or Namecheap) account → DNS management
5. Add the records Cloudflare specifies (usually two CNAME records)
6. Wait 5–15 minutes for DNS to propagate

After this, `hearthglow.ca` loads your site. Cloudflare handles SSL (https) automatically — no cost.

---

## Step 5 — Set up matt@hearthglow.ca email

Options (cheapest first):

| Option | Cost | Setup |
|--------|------|-------|
| Google Workspace (Starter) | ~$8 CAD/month | Full Gmail at your domain. Easiest to use. |
| Cloudflare Email Routing | Free | Forwards hearthglow.ca email to your personal Gmail. No sending from the custom address. |
| Zoho Mail (free tier) | Free | 5GB, webmail only. Works for Season 1. |

**Recommended for Season 1:** Cloudflare Email Routing (free). Set it up so anything sent to matt@hearthglow.ca forwards to your personal Gmail. You reply from your personal address but the contact page shows the professional address. Upgrade to Google Workspace in Season 2.

To set up Cloudflare Email Routing:
1. Cloudflare dashboard → your domain → Email → Email Routing
2. Add routing rule: `matt@hearthglow.ca` → `larocque.matt@gmail.com`
3. Done. No cost.

---

## Checklist before go-live

- [ ] hearthglow.ca domain registered
- [ ] Formspree account created and form ID inserted into index.html
- [ ] Site deployed to Cloudflare Pages
- [ ] Custom domain pointing to Cloudflare Pages
- [ ] SSL certificate active (automatic via Cloudflare)
- [ ] Quote form tested — submission arrives at matt@hearthglow.ca
- [ ] Email forwarding active (matt@hearthglow.ca → personal Gmail)
- [ ] Site loads correctly on mobile
- [ ] GBP listing created and links to hearthglow.ca

---

## Pre-season update needed (before October 1)

Once Nicole confirms pricing, update the tier cards in `index.html` to show actual starting prices instead of "request a quote." Search for:

```
Pricing varies by property size.
```

Replace with the confirmed starting price for each tier.

---

*Hearthglow Website Setup Guide | June 2026*
