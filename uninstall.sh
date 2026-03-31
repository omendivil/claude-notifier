#!/usr/bin/env bash
# Claude Notifier uninstaller
set -euo pipefail

INSTALL_DIR="${HOME}/.config/claude-notifier"
SETTINGS_FILE="${HOME}/.claude/settings.json"
BACKUP_FILE="${SETTINGS_FILE}.backup-claude-notifier"

# shellcheck disable=SC2034  # RED used by err() if added later
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }

echo ""
echo "  Claude Notifier Uninstaller"
echo "  ───────────────────────────"
echo ""

# Step 1: Remove hooks from settings.json
if [[ -f "$SETTINGS_FILE" ]]; then
  info "Removing hooks from Claude Code settings..."
  if grep -q "claude-notifier" "$SETTINGS_FILE" 2>/dev/null; then
    CLEANED=$(jq '
      if .hooks then
        .hooks |= (
          with_entries(
            .value |= map(
              select(
                (.hooks // []) | all(
                  .command // "" | contains("claude-notifier") | not
                )
              )
            )
          ) | with_entries(select(.value | length > 0))
        )
      else . end
    ' "$SETTINGS_FILE")
    echo "$CLEANED" > "$SETTINGS_FILE"
    ok "Hooks removed from settings.json"
  else
    ok "No claude-notifier hooks found in settings.json"
  fi
  if [[ -f "$BACKUP_FILE" ]]; then
    echo ""
    read -rp "  Restore settings.json from pre-install backup? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      cp "$BACKUP_FILE" "$SETTINGS_FILE"
      ok "Restored from backup"
    fi
    rm -f "$BACKUP_FILE"
  fi
else
  warn "settings.json not found — skipping hook removal"
fi

# Step 1.5: Kill daemon if running
if [[ -f "${INSTALL_DIR}/.daemon.pid" ]]; then
  info "Stopping daemon..."
  daemon_pid=$(cat "${INSTALL_DIR}/.daemon.pid" 2>/dev/null)
  if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
    kill "$daemon_pid" 2>/dev/null || true
    ok "Daemon stopped"
  fi
  rm -f "${INSTALL_DIR}/.daemon.pid"
fi
rm -rf "${INSTALL_DIR}/.daemon.lock"

# Step 2: Remove installed files
if [[ -d "$INSTALL_DIR" ]]; then
  info "Removing installed files..."
  if [[ -f "${INSTALL_DIR}/config.conf" ]]; then
    read -rp "  Remove your customized config.conf? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      rm -rf "$INSTALL_DIR"
      ok "Removed ${INSTALL_DIR} (including config)"
    else
      rm -rf "${INSTALL_DIR:?}/bin" "${INSTALL_DIR:?}/lib" "${INSTALL_DIR:?}/sessions"
      rm -f "${INSTALL_DIR}/.blink.pid" "${INSTALL_DIR}/.last-working-notify" "${INSTALL_DIR}/.daemon.pid"
      rm -rf "${INSTALL_DIR}/.daemon.lock"
      ok "Removed ${INSTALL_DIR} (config.conf preserved)"
    fi
  else
    rm -rf "$INSTALL_DIR"
    ok "Removed ${INSTALL_DIR}"
  fi
else
  ok "Install directory not found — already removed"
fi

echo ""
info "Note: If the installer added 'allow_remote_control yes' to your kitty.conf,"
echo "      you may want to remove it manually if no other tools need it."
echo ""
echo -e "${GREEN}Uninstall complete!${NC}"
echo ""
