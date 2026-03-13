#!/usr/bin/env bash
# Persistent tab color logic

COLOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${COLOR_SCRIPT_DIR}/kitty.sh"

set_state_color() {
  local state="$1"

  case "$state" in
    permission)
      kitty_set_tab_color active_bg="${COLOR_PERMISSION:-#ff9500}"
      ;;
    done|idle)
      kitty_set_tab_color active_bg="${COLOR_DONE:-#34c759}"
      ;;
    working)
      kitty_set_tab_color active_bg="${COLOR_WORKING:-#007aff}"
      ;;
    normal)
      kitty_set_tab_color active_bg=NONE
      ;;
  esac
}
