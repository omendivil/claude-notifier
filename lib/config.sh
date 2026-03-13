#!/usr/bin/env bash
# Config loader with validation for claude-notifier
# Reads ~/.config/claude-notifier/config.conf with safe parsing (no eval/source)

CLAUDE_NOTIFIER_DIR="${HOME}/.config/claude-notifier"
CLAUDE_NOTIFIER_CONF="${CLAUDE_NOTIFIER_DIR}/config.conf"

# Defaults (used if config file missing or values invalid)
NOTIFY_BLINK=true
NOTIFY_COLOR=false
NOTIFY_DESKTOP=false
COLOR_PERMISSION="#ff9500"
COLOR_DONE="#34c759"
COLOR_WORKING="#007aff"
BLINK_FAST=0.1
BLINK_SLOW=0.3
DEBOUNCE_WORKING=3

load_config() {
  if [[ ! -f "$CLAUDE_NOTIFIER_CONF" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    # Must match KEY=VALUE format (uppercase + underscores only)
    if ! [[ "$line" =~ ^[A-Z_]+=.+$ ]]; then
      echo "claude-notifier: ignoring invalid config line: $line" >&2
      continue
    fi

    local key="${line%%=*}"
    local value="${line#*=}"

    # Strip surrounding quotes
    value="${value%\"}"
    value="${value#\"}"

    # Validate by key type
    case "$key" in
      NOTIFY_BLINK|NOTIFY_COLOR|NOTIFY_DESKTOP)
        if [[ "$value" != "true" && "$value" != "false" ]]; then
          echo "claude-notifier: invalid boolean for $key: $value (expected true/false)" >&2
          continue
        fi
        ;;
      COLOR_PERMISSION|COLOR_DONE|COLOR_WORKING)
        if ! [[ "$value" =~ ^#[0-9a-fA-F]{6}$ ]]; then
          echo "claude-notifier: invalid color for $key: $value (expected #rrggbb)" >&2
          continue
        fi
        ;;
      BLINK_FAST|BLINK_SLOW|DEBOUNCE_WORKING)
        if ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
          echo "claude-notifier: invalid number for $key: $value" >&2
          continue
        fi
        ;;
      *)
        echo "claude-notifier: ignoring unknown key: $key" >&2
        continue
        ;;
    esac

    # Set the variable (printf -v works on bash 3.2+, unlike declare -g)
    printf -v "$key" '%s' "$value"
  done < "$CLAUDE_NOTIFIER_CONF"
}
