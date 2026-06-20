#!/usr/bin/env bash
# =============================================================================
# Hearthglow — SSH Key Setup
# =============================================================================
# Run this ONCE before using deploy.sh or any SSH-based script.
# Creates an SSH key pair and uploads the public key to CanSpace.
#
# Usage:  bash scripts/setup-ssh-key.sh
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Hearthglow — SSH Key Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Create key pair if it doesn't exist ────────────────────────────────────
if [[ -f "$SSH_KEY" ]]; then
  echo "✓ SSH key already exists at $SSH_KEY"
else
  echo "→ Generating SSH key pair..."
  ssh-keygen -t ed25519 -f "$SSH_KEY" -C "hearthglow-deploy" -N ""
  echo "✓ Key pair created: $SSH_KEY (private) and $SSH_KEY.pub (public)"
fi

# ── 2. Read the public key ────────────────────────────────────────────────────
PUB_KEY=$(cat "$SSH_KEY.pub")
echo ""
echo "Public key:"
echo "$PUB_KEY"
echo ""

# ── 3. Upload to cPanel via UAPI ──────────────────────────────────────────────
echo "→ Uploading public key to cPanel..."
RESULT=$(cpanel_api SSH import_key "key=$PUB_KEY" "name=hearthglow-deploy" 2>&1)

if echo "$RESULT" | grep -q '"status":1'; then
  echo "✓ SSH key uploaded to cPanel successfully"
else
  echo ""
  echo "⚠  Automatic upload may have failed. Manual steps:"
  echo "   1. Go to https://$CPANEL_HOST:$CPANEL_PORT"
  echo "   2. Security → SSH Access → Manage SSH Keys → Import Key"
  echo "   3. Paste the public key above"
  echo "   4. Then click 'Authorize' next to the imported key"
  echo ""
  echo "   Raw API response:"
  echo "$RESULT"
fi

# ── 4. Authorize the key if it isn't yet ─────────────────────────────────────
AUTHORIZE=$(cpanel_api SSH authkey "name=hearthglow-deploy" 2>&1)
echo ""
echo "→ Authorize attempt: $(echo "$AUTHORIZE" | python3 -c "import sys,json; d=json.load(sys.stdin); print('✓ Authorized' if d.get('status')==1 else '⚠ Manual auth may be needed')" 2>/dev/null || echo "(check manually)")"

# ── 5. Test connection ────────────────────────────────────────────────────────
echo ""
echo "→ Testing SSH connection (this may ask you to accept the host key)..."
if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
       -o ConnectTimeout=10 "$SSH_USER@$SSH_HOST" "echo 'SSH connection: OK'" 2>/dev/null; then
  echo "✓ SSH connection working"
else
  echo "⚠  SSH test failed. Check:"
  echo "   - config.sh values are correct"
  echo "   - SSH is enabled for your CanSpace account (default: yes on Medium plan)"
  echo "   - Key is authorized in cPanel SSH Access"
fi

echo ""
echo "Done. Run 'bash scripts/deploy.sh' to push your site."
