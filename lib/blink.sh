#!/usr/bin/env bash
# Tab blink logic with PID tracking and cancellation

BLINK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BLINK_SCRIPT_DIR}/kitty.sh"

BLINK_PID_FILE="${HOME}/.config/claude-notifier/.blink.pid"

_kill_previous_blink() {
  if [[ -f "$BLINK_PID_FILE" ]]; then
    local old_pid
    old_pid=$(cat "$BLINK_PID_FILE" 2>/dev/null)
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
    fi
    rm -f "$BLINK_PID_FILE"
  fi
}

_do_blink() {
  local state="$1"
  local fast="${BLINK_FAST:-0.1}"
  local slow="${BLINK_SLOW:-0.3}"

  case "$state" in
    permission)
      # 3 fast blinks — urgent
      for _ in 1 2 3; do
        kitty_set_tab_color active_bg="#ffffff"
        sleep "$fast"
        kitty_set_tab_color active_bg=NONE
        sleep "$fast"
      done
      ;;
    error)
      # 2 fast blinks — attention needed
      for _ in 1 2; do
        kitty_set_tab_color active_bg="#ffffff"
        sleep "$fast"
        kitty_set_tab_color active_bg=NONE
        sleep "$fast"
      done
      ;;
    done)
      # 2 slow pulses — gentle
      for _ in 1 2; do
        kitty_set_tab_color active_bg="#ffffff"
        sleep "$slow"
        kitty_set_tab_color active_bg=NONE
        sleep "$slow"
      done
      ;;
    idle)
      # 1 slow pulse — reminder
      kitty_set_tab_color active_bg="#ffffff"
      sleep "$slow"
      kitty_set_tab_color active_bg=NONE
      ;;
    working|researching)
      # 1 short flash — acknowledgment
      kitty_set_tab_color active_bg="#ffffff"
      sleep 0.15
      kitty_set_tab_color active_bg=NONE
      ;;
    waiting|normal)
      # No blink
      ;;
  esac

  # Clean up PID file
  rm -f "$BLINK_PID_FILE"
}

run_blink() {
  local state="$1"
  _kill_previous_blink

  _do_blink "$state" &
  echo $! > "$BLINK_PID_FILE"
}
