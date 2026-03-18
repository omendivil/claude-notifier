#!/usr/bin/env bash
# Persistent tab color logic

COLOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${COLOR_SCRIPT_DIR}/kitty.sh"

set_state_color() {
  local state="$1"

  case "$state" in
    permission)
      kitty_set_tab_color active_bg="${COLOR_PERMISSION:-#ff003c}"
      ;;
    done|waiting)
      kitty_set_tab_color active_bg="${COLOR_DONE:-#00ffd5}"
      ;;
    working)
      kitty_set_tab_color active_bg="${COLOR_WORKING:-#b026ff}"
      ;;
    researching)
      kitty_set_tab_color active_bg="${COLOR_RESEARCHING:-#007aff}"
      ;;
    error)
      kitty_set_tab_color active_bg="${COLOR_ERROR:-#ff6b00}"
      ;;
    normal|idle)
      kitty_set_tab_color active_bg=NONE
      ;;
  esac
}
