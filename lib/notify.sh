#!/usr/bin/env bash
# Desktop notification via kitten notify

NOTIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${NOTIFY_SCRIPT_DIR}/kitty.sh"

_extract_message() {
  local json="$1"
  [[ -z "$json" ]] && return

  # Prefer jq if available, fall back to grep
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r '.message // empty' 2>/dev/null
  else
    echo "$json" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 \
      | sed 's/.*"message"[[:space:]]*:[[:space:]]*"//;s/"$//'
  fi
}

send_notification() {
  local state="$1"
  local stdin_json="$2"

  case "$state" in
    permission)
      local message
      message=$(_extract_message "$stdin_json")
      [[ -z "$message" ]] && message="Claude needs permission"
      kitty_notify --title "Claude Code" "$message"
      ;;
    error)
      local error_msg
      error_msg=$(_extract_message "$stdin_json")
      [[ -z "$error_msg" ]] && error_msg="A tool encountered an error"
      kitty_notify --title "Claude Code" "$error_msg"
      ;;
    done)
      kitty_notify --title "Claude Code" "Claude is done"
      ;;
    working|researching|waiting|idle|normal)
      # No desktop notification for these states
      ;;
  esac
}
