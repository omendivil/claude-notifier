#!/usr/bin/env bash
# Shared helper for kitten @ commands
# Uses --self when KITTY_WINDOW_ID is available, falls back to --match pid:$PPID

kitty_set_tab_color() {
  if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
    kitten @ set-tab-color --self "$@" 2>/dev/null
  else
    kitten @ set-tab-color --match "pid:$PPID" "$@" 2>/dev/null
  fi
}

kitty_notify() {
  kitten notify "$@" 2>/dev/null
}
