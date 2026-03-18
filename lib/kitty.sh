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

kitty_set_tab_title() {
  if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
    kitten @ set-tab-title --match "id:${KITTY_WINDOW_ID}" "$@" 2>/dev/null
  else
    kitten @ set-tab-title --match "pid:$PPID" "$@" 2>/dev/null
  fi
}

kitty_notify() {
  kitten notify "$@" 2>/dev/null
}

# ── Daemon helpers (target by window ID, not --self) ──
kitty_set_tab_color_by_id() {
  local window_id="$1"; shift
  kitten @ set-tab-color --match "id:${window_id}" "$@" 2>/dev/null
}

kitty_set_tab_title_by_id() {
  local window_id="$1"; shift
  kitten @ set-tab-title --match "id:${window_id}" "$@" 2>/dev/null
}
