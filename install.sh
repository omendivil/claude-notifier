#!/usr/bin/env bash
# Claude Notifier installer
# Copies files, merges hooks into Claude Code settings, checks kitty config
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.config/claude-notifier"
SETTINGS_FILE="${HOME}/.claude/settings.json"
KITTY_CONF="${HOME}/.config/kitty/kitty.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
err()   { echo -e "${RED}[error]${NC} $1"; }

echo ""
echo "  Claude Notifier Installer"
echo "  ─────────────────────────"
echo ""

# Step 1: Check dependencies
info "Checking dependencies..."
missing=()
command -v bash &>/dev/null || missing+=("bash")
command -v jq &>/dev/null || missing+=("jq")
if ! command -v kitten &>/dev/null; then
  if ! command -v kitty &>/dev/null; then
    missing+=("kitten (part of kitty)")
  fi
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  err "Missing dependencies: ${missing[*]}"
  echo "  Install them and try again."
  echo "  - jq: brew install jq (macOS) or apt install jq (Linux)"
  echo "  - kitty: https://sw.kovidgoyal.net/kitty/binary/"
  exit 1
fi
ok "All dependencies found"

# Step 2: Copy files
info "Installing to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/lib"
cp "${SCRIPT_DIR}/bin/claude-notifier" "${INSTALL_DIR}/bin/"
cp "${SCRIPT_DIR}/bin/claude-notifier-daemon" "${INSTALL_DIR}/bin/"
cp "${SCRIPT_DIR}/lib/"*.sh "${INSTALL_DIR}/lib/"
chmod +x "${INSTALL_DIR}/bin/claude-notifier"
chmod +x "${INSTALL_DIR}/bin/claude-notifier-daemon"
mkdir -p "${INSTALL_DIR}/sessions"
if [[ ! -f "${INSTALL_DIR}/config.conf" ]]; then
  cp "${SCRIPT_DIR}/config/default.conf" "${INSTALL_DIR}/config.conf"
  ok "Config created at ${INSTALL_DIR}/config.conf"
else
  ok "Existing config preserved at ${INSTALL_DIR}/config.conf"
fi

# Step 3: Merge hooks into settings.json
info "Configuring Claude Code hooks..."
NOTIFIER_CMD="${INSTALL_DIR}/bin/claude-notifier"

HOOKS_JSON=$(jq -n --arg cmd "$NOTIFIER_CMD" '{
  UserPromptSubmit: [
    {hooks: [{type: "command", command: ($cmd + " --state working --stdin")}]}
  ],
  Notification: [
    {matcher: "permission_prompt", hooks: [{type: "command", command: ($cmd + " --state permission --stdin")}]},
    {matcher: "idle_prompt", hooks: [{type: "command", command: ($cmd + " --state waiting --stdin")}]}
  ],
  Stop: [
    {hooks: [{type: "command", command: ($cmd + " --state done --stdin")}]}
  ],
  PreToolUse: [
    {matcher: ".*", hooks: [{type: "command", command: ($cmd + " --state working --stdin")}]}
  ],
  PostToolUse: [
    {matcher: ".*", hooks: [{type: "command", command: ($cmd + " --state working --stdin")}]}
  ],
  PostToolUseFailure: [
    {matcher: ".*", hooks: [{type: "command", command: ($cmd + " --state error --stdin")}]}
  ],
  SubagentStart: [
    {matcher: ".*", hooks: [{type: "command", command: ($cmd + " --state researching --stdin")}]}
  ],
  SubagentStop: [
    {matcher: ".*", hooks: [{type: "command", command: ($cmd + " --state working --stdin")}]}
  ],
  SessionEnd: [
    {hooks: [{type: "command", command: ($cmd + " --cleanup --stdin")}]}
  ]
}')

mkdir -p "$(dirname "$SETTINGS_FILE")"
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup-claude-notifier"
ok "Settings backed up to ${SETTINGS_FILE}.backup-claude-notifier"

if grep -q "claude-notifier" "$SETTINGS_FILE" 2>/dev/null; then
  warn "Claude Notifier hooks already present in settings.json — skipping merge"
else
  MERGED=$(jq --argjson new_hooks "$HOOKS_JSON" '
    .hooks = (
      (.hooks // {}) |
      .UserPromptSubmit = ((.UserPromptSubmit // []) + $new_hooks.UserPromptSubmit) |
      .Notification = ((.Notification // []) + $new_hooks.Notification) |
      .Stop = ((.Stop // []) + $new_hooks.Stop) |
      .PreToolUse = ((.PreToolUse // []) + $new_hooks.PreToolUse) |
      .PostToolUse = ((.PostToolUse // []) + $new_hooks.PostToolUse) |
      .PostToolUseFailure = ((.PostToolUseFailure // []) + $new_hooks.PostToolUseFailure) |
      .SubagentStart = ((.SubagentStart // []) + $new_hooks.SubagentStart) |
      .SubagentStop = ((.SubagentStop // []) + $new_hooks.SubagentStop) |
      .SessionEnd = ((.SessionEnd // []) + $new_hooks.SessionEnd)
    )
  ' "$SETTINGS_FILE")
  echo "$MERGED" > "$SETTINGS_FILE"
  ok "Hooks merged into ${SETTINGS_FILE}"
fi

# Step 4: Check kitty config
info "Checking Kitty configuration..."
if [[ -f "$KITTY_CONF" ]]; then
  if grep -q "allow_remote_control" "$KITTY_CONF"; then
    rc_value=$(grep "allow_remote_control" "$KITTY_CONF" | tail -1 | awk '{print $2}')
    if [[ "$rc_value" == "no" ]]; then
      warn "allow_remote_control is set to 'no' in kitty.conf"
      echo "  Claude Notifier needs remote control enabled."
      read -rp "  Add 'allow_remote_control yes' to kitty.conf? [y/N] " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "" >> "$KITTY_CONF"
        echo "# Added by Claude Notifier" >> "$KITTY_CONF"
        echo "allow_remote_control yes" >> "$KITTY_CONF"
        ok "Added allow_remote_control to kitty.conf (restart Kitty to apply)"
      else
        warn "Skipped. Add 'allow_remote_control yes' to kitty.conf manually."
      fi
    else
      ok "allow_remote_control is enabled (${rc_value})"
    fi
  else
    warn "allow_remote_control not found in kitty.conf"
    read -rp "  Add 'allow_remote_control yes' to kitty.conf? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      echo "" >> "$KITTY_CONF"
      echo "# Added by Claude Notifier" >> "$KITTY_CONF"
      echo "allow_remote_control yes" >> "$KITTY_CONF"
      ok "Added allow_remote_control to kitty.conf (restart Kitty to apply)"
    else
      warn "Skipped. Add 'allow_remote_control yes' to kitty.conf manually."
    fi
  fi
else
  warn "kitty.conf not found at ${KITTY_CONF}"
  echo "  Ensure 'allow_remote_control yes' is in your Kitty config."
fi

# Step 5: Validate environment
info "Checking Kitty environment..."
if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
  ok "KITTY_WINDOW_ID detected (${KITTY_WINDOW_ID})"
else
  warn "KITTY_WINDOW_ID not set — are you running inside Kitty?"
  echo "  Claude Notifier will fall back to PID-based tab matching."
  echo "  For best results, run this installer inside a Kitty terminal."
fi

# Step 6: Test
info "Running test blink..."
if "${INSTALL_DIR}/bin/claude-notifier" --test 2>/dev/null; then
  ok "Test blink sent! Did you see the tab flash?"
else
  warn "Test blink failed — check that Kitty remote control is enabled"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "  Config: ${INSTALL_DIR}/config.conf"
echo "  To customize: edit the config file to enable color or desktop notification modes"
echo "  To uninstall: run ./uninstall.sh from this directory"
echo ""
