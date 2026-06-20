#!/usr/bin/env bash
# =============================================================================
# Hearthglow — DNS Record Setup via cPanel UAPI
# =============================================================================
# Adds all required DNS records for hearthglow.ca:
#   - MX  : Email delivery
#   - SPF : Email authentication (spam protection)
#   - DMARC: Email policy enforcement
#   - CAA : Restrict who can issue SSL certs for the domain
#   - CNAME: www → hearthglow.ca redirect
#
# Note: The A record (pointing the domain to the server IP) is added by
# CanSpace automatically when you set your nameservers. This script handles
# the supplementary records only.
#
# Usage:  bash scripts/setup-dns.sh
# Usage:  bash scripts/setup-dns.sh --check-only    # Just verify, no changes
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

CHECK_ONLY=false
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=true

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — DNS Setup for $DOMAIN"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Helper: add a DNS record via cPanel UAPI ──────────────────────────────────
add_dns_record() {
  local type="$1"
  local name="$2"
  local value="$3"
  local ttl="${4:-3600}"

  if [[ "$CHECK_ONLY" == true ]]; then
    echo "  [CHECK-ONLY] Would add: $type $name → $value"
    return 0
  fi

  RESULT=$(cpanel_api ZoneEdit add_zone_record \
    "domain=$DOMAIN" \
    "name=$name" \
    "type=$type" \
    "txtdata=$value" \
    "ttl=$ttl" 2>&1)

  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
  if [[ "$STATUS" == "1" ]]; then
    echo "  ✓ Added: $type $name → $value"
  else
    MSG=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0] if errs else 'already exists or unknown')" 2>/dev/null || echo "check cPanel")
    echo "  ⚠  $type $name: $MSG"
  fi
}

# ── Helper: check DNS propagation ─────────────────────────────────────────────
check_dns() {
  local type="$1"
  local name="$2"
  local expected="$3"

  ACTUAL=$(dig +short "$type" "$name" 2>/dev/null | head -1 || echo "")
  if [[ -n "$ACTUAL" ]]; then
    echo "  ✓ $type $name = $ACTUAL"
  else
    echo "  ⚠  $type $name not resolving yet (DNS propagation may take up to 24h)"
  fi
}

echo "── Step 1: Nameserver check ──────────────────────────────────────────────"
echo ""
echo "→ Checking if hearthglow.ca is pointing to CanSpace nameservers..."
NS_RECORDS=$(dig +short NS "$DOMAIN" 2>/dev/null || echo "")
if echo "$NS_RECORDS" | grep -qi "canspace"; then
  echo "  ✓ Nameservers are pointing to CanSpace"
  echo "  $NS_RECORDS"
else
  echo "  ⚠  Nameservers not yet pointing to CanSpace, or not propagated"
  echo "  Current NS: $NS_RECORDS"
  echo ""
  echo "  ACTION REQUIRED: In your CanSpace client area:"
  echo "  Domains → hearthglow.ca → Change Nameservers"
  echo "  Set to:  ns1.canspace.ca"
  echo "           ns2.canspace.ca"
  echo ""
  echo "  After changing nameservers, wait 1-24 hours before continuing."
  echo ""
  if [[ "$CHECK_ONLY" == false ]]; then
    read -rp "Continue anyway to pre-configure DNS records? [y/N] " cont
    [[ "$cont" != "y" && "$cont" != "Y" ]] && exit 0
  fi
fi

echo ""
echo "── Step 2: MX records (email delivery) ──────────────────────────────────"
echo ""
# CanSpace sets MX records automatically — we just verify
MX=$(dig +short MX "$DOMAIN" 2>/dev/null || echo "")
if [[ -n "$MX" ]]; then
  echo "  ✓ MX records found: $MX"
else
  echo "  ⚠  No MX records found. CanSpace adds these automatically."
  echo "  If missing after 24h: cPanel → Email Accounts → check domain"
  # Try to add via API anyway
  add_dns_record "MX" "$DOMAIN." "mail.$DOMAIN" 3600
fi

echo ""
echo "── Step 3: SPF record (email sender authentication) ─────────────────────"
echo ""
SPF=$(dig +short TXT "$DOMAIN" 2>/dev/null | grep "v=spf1" | tr -d '"' || echo "")
if [[ -n "$SPF" ]]; then
  echo "  ✓ SPF record exists: $SPF"
else
  echo "→ Adding SPF record..."
  add_dns_record "TXT" "$DOMAIN." "v=spf1 include:canspace.ca ~all"
fi

echo ""
echo "── Step 4: DMARC record (email policy) ──────────────────────────────────"
echo ""
DMARC=$(dig +short TXT "_dmarc.$DOMAIN" 2>/dev/null | tr -d '"' || echo "")
if [[ -n "$DMARC" ]]; then
  echo "  ✓ DMARC record exists: $DMARC"
else
  echo "→ Adding DMARC record (monitor mode — safe to start with)..."
  add_dns_record "TXT" "_dmarc.$DOMAIN." "v=DMARC1; p=none; rua=mailto:matt@hearthglow.ca; ruf=mailto:matt@hearthglow.ca; fo=1"
fi

echo ""
echo "── Step 5: CAA record (SSL certificate authority restriction) ────────────"
echo ""
CAA=$(dig +short CAA "$DOMAIN" 2>/dev/null || echo "")
if [[ -n "$CAA" ]]; then
  echo "  ✓ CAA record exists: $CAA"
else
  echo "→ Adding CAA record (Let's Encrypt only — CanSpace uses Let's Encrypt)..."
  add_dns_record "CAA" "$DOMAIN." "0 issue \"letsencrypt.org\""
fi

echo ""
echo "── Step 6: www CNAME ─────────────────────────────────────────────────────"
echo ""
WWW=$(dig +short CNAME "www.$DOMAIN" 2>/dev/null || echo "")
if [[ -n "$WWW" ]]; then
  echo "  ✓ www CNAME exists: $WWW"
else
  echo "→ Adding www CNAME → $DOMAIN..."
  RESULT=$(cpanel_api ZoneEdit add_zone_record \
    "domain=$DOMAIN" \
    "name=www.$DOMAIN." \
    "type=CNAME" \
    "cname=$DOMAIN." \
    "ttl=3600" 2>&1)
  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
  [[ "$STATUS" == "1" ]] && echo "  ✓ www CNAME added" || echo "  ⚠  CNAME add result: check cPanel Zone Editor"
fi

echo ""
echo "── Full propagation check ────────────────────────────────────────────────"
echo ""
check_dns "A"     "$DOMAIN"        "server IP"
check_dns "MX"    "$DOMAIN"        "mail server"
check_dns "TXT"   "$DOMAIN"        "SPF"
check_dns "TXT"   "_dmarc.$DOMAIN" "DMARC"
check_dns "CNAME" "www.$DOMAIN"    "CNAME"

echo ""
echo "Done. Full DNS propagation can take up to 24 hours after nameserver change."
echo "Run 'bash scripts/setup-dns.sh --check-only' at any time to recheck."
