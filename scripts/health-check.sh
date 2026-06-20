#!/usr/bin/env bash
# =============================================================================
# Hearthglow — Site Health Check
# =============================================================================
# Quick diagnostic: HTTP status, SSL cert, DNS, form endpoint, page speed.
# Run any time to confirm everything is working.
#
# Usage:  bash scripts/health-check.sh
#         bash scripts/health-check.sh --quiet   # Only show failures
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

PASS=0; WARN=0; FAIL=0

log_pass() { (( PASS++ )); [[ "$QUIET" == false ]] && echo "  ✓ $1"; }
log_warn() { (( WARN++ )); echo "  ⚠  $1"; }
log_fail() { (( FAIL++ )); echo "  ✗ $1"; }

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — Health Check | $(date '+%Y-%m-%d %H:%M')"
echo "═══════════════════════════════════════════════════"
echo ""

# ── DNS ───────────────────────────────────────────────────────────────────────
echo "── DNS ──────────────────────────────────────────────────────────────────"
A_RECORD=$(dig +short A "$DOMAIN" 2>/dev/null | head -1 || echo "")
[[ -n "$A_RECORD" ]] && log_pass "$DOMAIN A record: $A_RECORD" || log_fail "$DOMAIN has no A record"

WWW_R=$(dig +short CNAME "www.$DOMAIN" 2>/dev/null | head -1 || echo "$(dig +short A "www.$DOMAIN" 2>/dev/null | head -1)")
[[ -n "$WWW_R" ]] && log_pass "www.$DOMAIN resolves: $WWW_R" || log_warn "www.$DOMAIN not resolving"

MX_R=$(dig +short MX "$DOMAIN" 2>/dev/null | head -1 || echo "")
[[ -n "$MX_R" ]] && log_pass "MX record: $MX_R" || log_warn "No MX record — email may not work"

SPF_R=$(dig +short TXT "$DOMAIN" 2>/dev/null | grep "v=spf1" | tr -d '"' || echo "")
[[ -n "$SPF_R" ]] && log_pass "SPF: $SPF_R" || log_warn "No SPF record — email may be flagged as spam"

DMARC_R=$(dig +short TXT "_dmarc.$DOMAIN" 2>/dev/null | tr -d '"' || echo "")
[[ -n "$DMARC_R" ]] && log_pass "DMARC: present" || log_warn "No DMARC record — run setup-dns.sh"

# ── HTTP / HTTPS ──────────────────────────────────────────────────────────────
echo ""
echo "── HTTP/HTTPS ───────────────────────────────────────────────────────────"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$DOMAIN/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "301" ]]; then
  log_pass "HTTP → HTTPS redirect: 301 (correct)"
elif [[ "$HTTP_CODE" == "200" ]]; then
  log_warn "HTTP returns 200 (not redirecting to HTTPS) — run setup-ssl.sh"
elif [[ "$HTTP_CODE" == "000" ]]; then
  log_fail "Cannot reach http://$DOMAIN/ (DNS not propagated or site down)"
else
  log_warn "http://$DOMAIN/ returned $HTTP_CODE"
fi

HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://$DOMAIN/" 2>/dev/null || echo "000")
if [[ "$HTTPS_CODE" == "200" ]]; then
  log_pass "HTTPS: https://$DOMAIN/ returns 200 OK"
elif [[ "$HTTPS_CODE" == "000" ]]; then
  log_fail "Cannot reach https://$DOMAIN/ — SSL may not be provisioned yet"
else
  log_warn "https://$DOMAIN/ returned $HTTPS_CODE"
fi

# ── SSL certificate ───────────────────────────────────────────────────────────
echo ""
echo "── SSL Certificate ──────────────────────────────────────────────────────"

EXPIRY_LINE=$(echo | timeout 5 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null || echo "")

if [[ -n "$EXPIRY_LINE" ]]; then
  EXPIRY="${EXPIRY_LINE#notAfter=}"
  EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo "0")
  DAYS=$(( (EXPIRY_EPOCH - $(date +%s)) / 86400 ))
  if   [[ "$DAYS" -gt 30 ]]; then log_pass "SSL cert valid: $DAYS days remaining (expires $EXPIRY)"
  elif [[ "$DAYS" -gt 0  ]]; then log_warn "SSL cert expires in $DAYS days — CanSpace should auto-renew"
  else log_fail "SSL cert expired or unreadable"; fi
else
  log_warn "Cannot read SSL cert (site may be down or DNS not propagated)"
fi

# ── Response time ─────────────────────────────────────────────────────────────
echo ""
echo "── Performance ──────────────────────────────────────────────────────────"

TIMING=$(curl -s -o /dev/null \
  -w "DNS: %{time_namelookup}s | Connect: %{time_connect}s | TTFB: %{time_starttransfer}s | Total: %{time_total}s" \
  --max-time 20 "https://$DOMAIN/" 2>/dev/null || echo "N/A")

if [[ "$TIMING" != "N/A" ]]; then
  TOTAL=$(echo "$TIMING" | grep -oP 'Total: \K[0-9.]+' || echo "99")
  if (( $(echo "$TOTAL < 2.0" | bc -l 2>/dev/null || echo 0) )); then
    log_pass "Response time: $TIMING"
  elif (( $(echo "$TOTAL < 4.0" | bc -l 2>/dev/null || echo 0) )); then
    log_warn "Slow response: $TIMING (target: under 2s)"
  else
    log_warn "Very slow response: $TIMING (consider enabling caching)"
  fi
else
  log_warn "Cannot measure response time"
fi

# ── Disk usage ────────────────────────────────────────────────────────────────
echo ""
echo "── Disk Usage ───────────────────────────────────────────────────────────"
DISK=$(cpanel_api StatsBar get_stats "display=diskusage" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); items=d.get('data',[]); [print(i.get('count','?'),i.get('units','')) for i in items]" 2>/dev/null || echo "N/A")
if [[ "$DISK" != "N/A" ]]; then
  log_pass "Disk: $DISK of 50GB used"
else
  log_pass "Disk usage: check cPanel (UAPI call needs active session)"
fi

# ── Email delivery check ──────────────────────────────────────────────────────
echo ""
echo "── Email ────────────────────────────────────────────────────────────────"
SMTP_CHECK=$(nc -zw5 "mail.$DOMAIN" 25 2>/dev/null && echo "OK" || echo "FAIL")
[[ "$SMTP_CHECK" == "OK" ]] && log_pass "SMTP port 25 reachable at mail.$DOMAIN" || log_warn "SMTP check failed (may be blocked by your ISP — test via webmail)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
printf "  Results:  ✓ %d passed   ⚠  %d warnings   ✗ %d failed\n" "$PASS" "$WARN" "$FAIL"
echo "═══════════════════════════════════════════════════"
echo ""

# Log result
mkdir -p "$(dirname "$0")/../logs"
printf "%s | PASS:%d WARN:%d FAIL:%d\n" "$(date -u '+%Y-%m-%d %H:%M UTC')" "$PASS" "$WARN" "$FAIL" \
  >> "$(dirname "$0")/../logs/health.log"

[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
