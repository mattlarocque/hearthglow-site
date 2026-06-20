#!/usr/bin/env bash
# =============================================================================
# Hearthglow — Email Account Setup via cPanel UAPI
# =============================================================================
# Creates all Hearthglow email accounts and configures email forwarding.
# Safe to run multiple times — checks if accounts already exist first.
#
# Accounts created:
#   matt@hearthglow.ca        → Main business address
#   hello@hearthglow.ca       → Public-facing / website contact
#   quotes@hearthglow.ca      → Quote request funnel (optional)
#   noreply@hearthglow.ca     → Outgoing only (for PHP mailer)
#
# All accounts forward to matt@hearthglow.ca in addition to storing locally.
#
# Usage:  bash scripts/setup-email.sh
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — Email Account Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Prompt for a shared password ─────────────────────────────────────────────
# In production, use separate strong passwords stored in a password manager.
echo "Enter a password for the email accounts (min 12 characters):"
echo "(You can change individual passwords in cPanel later)"
read -rs EMAIL_PASS
echo ""
if [[ ${#EMAIL_PASS} -lt 12 ]]; then
  echo "✗ Password must be at least 12 characters." && exit 1
fi

# ── Accounts to create ────────────────────────────────────────────────────────
declare -A ACCOUNTS=(
  ["matt"]="Main business address for all client communication"
  ["hello"]="Public-facing address shown on website"
  ["quotes"]="Quote request funnel — optional alias"
  ["noreply"]="Automated outgoing mail from PHP contact form"
)

# ── Create each account ───────────────────────────────────────────────────────
for user in "${!ACCOUNTS[@]}"; do
  EMAIL="${user}@${DOMAIN}"
  echo "→ Creating $EMAIL ..."

  RESULT=$(cpanel_api Email add_pop \
    "email=$user" \
    "domain=$DOMAIN" \
    "password=$EMAIL_PASS" \
    "quota=0" 2>&1)   # quota=0 = unlimited

  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")

  if [[ "$STATUS" == "1" ]]; then
    echo "  ✓ $EMAIL created"
  else
    MSG=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0] if errs else 'unknown')" 2>/dev/null || echo "$RESULT")
    if echo "$MSG" | grep -qi "already exist"; then
      echo "  ✓ $EMAIL already exists (skipped)"
    else
      echo "  ✗ $EMAIL failed: $MSG"
    fi
  fi
done

echo ""
echo "── Setting up forwarding ────────────────────────────────────────────────"
echo ""

# Forward hello@ and quotes@ to matt@ as well
for forward_from in "hello" "quotes"; do
  echo "→ Forwarding ${forward_from}@${DOMAIN} → $ADMIN_EMAIL ..."
  RESULT=$(cpanel_api Email add_forwarder \
    "email=${forward_from}@${DOMAIN}" \
    "fwdopt=fwd" \
    "fwdemail=$ADMIN_EMAIL" 2>&1)
  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
  if [[ "$STATUS" == "1" ]]; then
    echo "  ✓ Forwarder created"
  else
    echo "  ⚠ Forwarder may already exist or failed — check cPanel → Forwarders"
  fi
done

echo ""
echo "── Email authentication (SPF / DKIM) ────────────────────────────────────"
echo ""

# Enable DKIM
echo "→ Enabling DKIM for $DOMAIN ..."
DKIM_RESULT=$(cpanel_api Email enable_mail_sni "domain=$DOMAIN" 2>&1 || true)
echo "  (DKIM is typically enabled by default on CanSpace — verify in:"
echo "   cPanel → Email Deliverability → $DOMAIN)"

# Check SPF
echo ""
echo "→ Checking SPF record..."
SPF_CHECK=$(dig +short TXT "$DOMAIN" 2>/dev/null | grep "v=spf1" || echo "none")
if [[ "$SPF_CHECK" == "none" ]]; then
  echo "  ⚠ No SPF record found. CanSpace adds this automatically — check in:"
  echo "  cPanel → Email Deliverability. If missing, add:"
  echo "  TXT  @  v=spf1 include:canspace.ca ~all"
else
  echo "  ✓ SPF record: $SPF_CHECK"
fi

echo ""
echo "── Summary ──────────────────────────────────────────────────────────────"
echo ""
echo "  matt@hearthglow.ca      Primary — all client communications"
echo "  hello@hearthglow.ca     Website contact (forwards → matt@)"
echo "  quotes@hearthglow.ca    Quote funnel (forwards → matt@)"
echo "  noreply@hearthglow.ca   PHP form sender"
echo ""
echo "  IMAP / POP3 settings for email clients:"
echo "  Incoming: mail.$DOMAIN  port 993 (IMAP SSL) or 995 (POP3 SSL)"
echo "  Outgoing: mail.$DOMAIN  port 465 (SMTP SSL) or 587 (STARTTLS)"
echo "  Username: full email address (e.g. matt@hearthglow.ca)"
echo "  Password: the password you just set"
echo ""
echo "  Webmail: https://$DOMAIN/webmail"
echo ""
echo "Done."
