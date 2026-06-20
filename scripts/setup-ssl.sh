#!/usr/bin/env bash
# =============================================================================
# Hearthglow — SSL Certificate Setup and HTTPS Enforcement
# =============================================================================
# Verifies the Enhanced SSL cert (already provisioned by CanSpace) and
# ensures HTTPS redirect is in place via .htaccess on the server.
#
# CanSpace Medium automatically provisions a Let's Encrypt SSL cert when DNS
# is pointing to their servers. This script checks status and enforces HTTPS.
#
# Usage:  bash scripts/setup-ssl.sh
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — SSL + HTTPS Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Check current SSL status ───────────────────────────────────────────────
echo "── Step 1: Check SSL certificate ────────────────────────────────────────"
echo ""

SSL_INFO=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "FAILED")

if [[ "$SSL_INFO" == "FAILED" ]]; then
  echo "  ⚠  Cannot reach $DOMAIN:443 — DNS may not be pointing to CanSpace yet"
  echo "  Once DNS propagates, re-run this script."
else
  echo "  ✓ SSL certificate found:"
  echo "$SSL_INFO" | sed 's/^/     /'

  # Check expiry
  EXPIRY=$(echo "$SSL_INFO" | grep "notAfter" | cut -d= -f2)
  EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo "0")
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

  if [[ "$DAYS_LEFT" -gt 30 ]]; then
    echo "  ✓ Certificate valid for $DAYS_LEFT more days"
  elif [[ "$DAYS_LEFT" -gt 0 ]]; then
    echo "  ⚠  Certificate expires in $DAYS_LEFT days — CanSpace should auto-renew"
  else
    echo "  ✗ Certificate may be expired — contact CanSpace support immediately"
  fi
fi

echo ""
echo "── Step 2: Install HTTPS redirect via .htaccess ─────────────────────────"
echo ""

# Create/update .htaccess on the server with HTTPS redirect + security headers
HTACCESS_CONTENT='# Hearthglow — HTTPS redirect and security headers
# Managed by setup-ssl.sh — do not edit manually

# ── Force HTTPS ───────────────────────────────────────────────────────────────
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# ── Force www → non-www ───────────────────────────────────────────────────────
RewriteCond %{HTTP_HOST} ^www\.(.+)$ [NC]
RewriteRule ^ https://%1%{REQUEST_URI} [L,R=301]

# ── Security headers ──────────────────────────────────────────────────────────
<IfModule mod_headers.c>
  Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains" env=HTTPS
  Header always set X-Frame-Options "SAMEORIGIN"
  Header always set X-Content-Type-Options "nosniff"
  Header always set Referrer-Policy "strict-origin-when-cross-origin"
  Header always set Permissions-Policy "camera=(), microphone=(), geolocation=()"
  Header always set Content-Security-Policy "default-src '"'"'self'"'"'; script-src '"'"'self'"'"' '"'"'unsafe-inline'"'"' https://fonts.googleapis.com; style-src '"'"'self'"'"' '"'"'unsafe-inline'"'"' https://fonts.googleapis.com https://fonts.gstatic.com; font-src '"'"'self'"'"' https://fonts.gstatic.com; img-src '"'"'self'"'"' data: https:; form-action '"'"'self'"'"' https://formspree.io;"
</IfModule>

# ── Compression ───────────────────────────────────────────────────────────────
<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/css application/javascript application/json
</IfModule>

# ── Browser caching ───────────────────────────────────────────────────────────
<IfModule mod_expires.c>
  ExpiresActive On
  ExpiresByType text/html                "access plus 1 hour"
  ExpiresByType text/css                 "access plus 1 month"
  ExpiresByType application/javascript   "access plus 1 month"
  ExpiresByType image/png                "access plus 1 year"
  ExpiresByType image/jpg                "access plus 1 year"
  ExpiresByType image/jpeg               "access plus 1 year"
  ExpiresByType image/webp               "access plus 1 year"
  ExpiresByType image/svg+xml            "access plus 1 month"
  ExpiresByType font/woff2               "access plus 1 year"
</IfModule>

# ── PHP mailer: protect sensitive paths ──────────────────────────────────────
<Files "config.sh">
  Order allow,deny
  Deny from all
</Files>
<Files ".env">
  Order allow,deny
  Deny from all
</Files>
'

echo "$HTACCESS_CONTENT" | ssh -i "$SSH_KEY" -p "$SSH_PORT" \
  "$SSH_USER@$SSH_HOST" \
  "cat > $REMOTE_WEBROOT/.htaccess" 2>/dev/null && \
  echo "  ✓ .htaccess installed on server" || \
  echo "  ⚠  SSH upload failed — manually create .htaccess (see README.md)"

echo ""
echo "── Step 3: Verify HTTPS redirect ────────────────────────────────────────"
echo ""

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$DOMAIN/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "301" || "$HTTP_CODE" == "302" ]]; then
  echo "  ✓ HTTP → HTTPS redirect active (HTTP returns $HTTP_CODE)"
elif [[ "$HTTP_CODE" == "000" ]]; then
  echo "  ⚠  Cannot reach $DOMAIN yet — DNS may still be propagating"
else
  echo "  ⚠  Expected 301 redirect, got HTTP $HTTP_CODE — check .htaccess"
fi

HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$DOMAIN/" 2>/dev/null || echo "000")
if [[ "$HTTPS_CODE" == "200" ]]; then
  echo "  ✓ HTTPS site is live: https://$DOMAIN/ returns 200 OK"
else
  echo "  ⚠  HTTPS returned $HTTPS_CODE — may still be propagating"
fi

echo ""
echo "Done. Re-run at any time to verify SSL status."
echo "CanSpace auto-renews Let's Encrypt certs before expiry — no manual action needed."
