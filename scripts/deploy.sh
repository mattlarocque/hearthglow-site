#!/usr/bin/env bash
# =============================================================================
# Hearthglow — Site Deployment Script
# =============================================================================
# Pushes all website files to CanSpace via rsync over SSH.
# Excludes scripts/, backups/, *.md, and config files from the upload.
#
# Usage:  bash scripts/deploy.sh           # Deploy and verify
#         bash scripts/deploy.sh --dry-run # Preview what would be uploaded
#         bash scripts/deploy.sh --force   # Skip confirmation prompt
#
# Prerequisites: setup-ssh-key.sh must have been run first.
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

DRY_RUN=false
FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
  [[ "$arg" == "--force"   ]] && FORCE=true
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — Deploying to $DOMAIN"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Confirm unless --force ────────────────────────────────────────────────────
if [[ "$FORCE" == false && "$DRY_RUN" == false ]]; then
  read -rp "Deploy to $REMOTE_WEBROOT on $SSH_HOST? [y/N] " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Aborted." && exit 0
fi

# ── Build rsync exclude list ──────────────────────────────────────────────────
EXCLUDES=(
  --exclude="scripts/"
  --exclude="backups/"
  --exclude="*.md"
  --exclude="*.sh"
  --exclude=".git/"
  --exclude=".gitignore"
  --exclude="*.log"
  --exclude="config.sh"
  --exclude=".DS_Store"
  --exclude="Thumbs.db"
)

# ── Run rsync ─────────────────────────────────────────────────────────────────
RSYNC_OPTS=(-avz --delete --progress)
[[ "$DRY_RUN" == true ]] && RSYNC_OPTS+=(--dry-run) && echo "DRY RUN — no files will be changed"

echo "→ Syncing $LOCAL_WEBROOT/ → $SSH_USER@$SSH_HOST:$REMOTE_WEBROOT/"
echo ""

rsync "${RSYNC_OPTS[@]}" "${EXCLUDES[@]}" \
  -e "ssh -i $SSH_KEY -p $SSH_PORT" \
  "$LOCAL_WEBROOT/" \
  "$SSH_USER@$SSH_HOST:$REMOTE_WEBROOT/"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "Dry run complete. Run without --dry-run to deploy."
  exit 0
fi

# ── Verify deployment ─────────────────────────────────────────────────────────
echo ""
echo "→ Verifying deployment..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://$DOMAIN/" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✓ https://$DOMAIN/ is live and returning 200 OK"
elif [[ "$HTTP_CODE" == "301" || "$HTTP_CODE" == "302" ]]; then
  FINAL=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 15 "https://$DOMAIN/" 2>/dev/null || echo "000")
  echo "✓ Redirect detected → final status: $FINAL"
elif [[ "$HTTP_CODE" == "000" ]]; then
  echo "⚠  Could not reach $DOMAIN (DNS may not be pointing to CanSpace yet)"
  echo "   Files were uploaded. Visit cPanel → File Manager to verify."
else
  echo "⚠  Unexpected HTTP $HTTP_CODE — check the site manually"
fi

# ── Log deployment ────────────────────────────────────────────────────────────
mkdir -p "$LOCAL_WEBROOT/logs"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') | deployed | HTTP $HTTP_CODE" \
  >> "$LOCAL_WEBROOT/logs/deploy.log"
echo ""
echo "✓ Deployment complete. Log: logs/deploy.log"
