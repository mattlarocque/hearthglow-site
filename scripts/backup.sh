#!/usr/bin/env bash
# =============================================================================
# Hearthglow — Backup Script
# =============================================================================
# Triggers a full cPanel backup and downloads it to your local machine.
# CanSpace already runs nightly automated backups — this script lets you
# trigger and download on-demand backups before major changes.
#
# Usage:  bash scripts/backup.sh              # Full backup + download
#         bash scripts/backup.sh --list       # List available backups
#         bash scripts/backup.sh --download   # Download most recent backup only
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

MODE="full"
[[ "${1:-}" == "--list" ]] && MODE="list"
[[ "${1:-}" == "--download" ]] && MODE="download"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — Backup Management"
echo "═══════════════════════════════════════════════════"
echo ""

mkdir -p "$LOCAL_BACKUP_DIR"

# ── LIST mode ─────────────────────────────────────────────────────────────────
if [[ "$MODE" == "list" ]]; then
  echo "→ Listing available backups on server..."
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" \
    "ls -lh ~/backup/*.tar.gz 2>/dev/null || echo 'No backups found in ~/backup/'" 2>/dev/null
  echo ""
  echo "Local backups in $LOCAL_BACKUP_DIR:"
  ls -lh "$LOCAL_BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "(none)"
  exit 0
fi

# ── TRIGGER full backup ───────────────────────────────────────────────────────
if [[ "$MODE" == "full" ]]; then
  echo "── Step 1: Trigger cPanel full backup ───────────────────────────────────"
  echo ""
  echo "→ Requesting full account backup via cPanel UAPI..."
  RESULT=$(cpanel_api Backup fullbackup_to_homedir \
    "email=$ADMIN_EMAIL" 2>&1)

  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
  if [[ "$STATUS" == "1" ]]; then
    echo "  ✓ Backup started. CanSpace will email $ADMIN_EMAIL when complete."
    echo "  This typically takes 1–5 minutes for a small site."
  else
    MSG=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0] if errs else 'check cPanel')" 2>/dev/null || echo "see raw output below")
    echo "  ⚠  Backup request result: $MSG"
    echo "  You can also trigger from cPanel → Backup → Generate/Download a Full Website Backup"
  fi

  echo ""
  echo "  Waiting 90 seconds for backup to complete..."
  for i in {1..9}; do
    sleep 10
    echo -n "  ."
  done
  echo ""
fi

# ── DOWNLOAD most recent backup ───────────────────────────────────────────────
echo ""
echo "── Step 2: Download backup ──────────────────────────────────────────────"
echo ""

# Find the most recent backup file on the server
BACKUP_FILE=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" \
  "ls -t ~/backup/backup-*.tar.gz 2>/dev/null | head -1" 2>/dev/null || echo "")

if [[ -z "$BACKUP_FILE" ]]; then
  echo "  ⚠  No backup file found yet. It may still be generating."
  echo "  Re-run with --download in a few minutes."
  exit 1
fi

BACKUP_NAME=$(basename "$BACKUP_FILE")
echo "→ Downloading $BACKUP_NAME to $LOCAL_BACKUP_DIR/ ..."

scp -i "$SSH_KEY" -P "$SSH_PORT" \
  "$SSH_USER@$SSH_HOST:$BACKUP_FILE" \
  "$LOCAL_BACKUP_DIR/$BACKUP_NAME"

SIZE=$(du -sh "$LOCAL_BACKUP_DIR/$BACKUP_NAME" | cut -f1)
echo "  ✓ Downloaded: $BACKUP_NAME ($SIZE)"

# ── Prune old local backups (keep last 5) ─────────────────────────────────────
echo ""
echo "→ Pruning old local backups (keeping 5 most recent)..."
ls -t "$LOCAL_BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -v

echo ""
echo "── Backup log ───────────────────────────────────────────────────────────"
echo ""
echo "$(date -u '+%Y-%m-%d %H:%M UTC') — $BACKUP_NAME ($SIZE)" >> "$LOCAL_BACKUP_DIR/backup.log"
echo "  Backup history saved to $LOCAL_BACKUP_DIR/backup.log"

echo ""
echo "  CanSpace also keeps nightly backups on their servers."
echo "  Restore: cPanel → Backup Wizard → Restore → Full Backup"
echo ""
echo "Done."
