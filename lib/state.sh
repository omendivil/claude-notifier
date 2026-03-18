#!/usr/bin/env bash
# Session state file management and daemon lifecycle

CLAUDE_NOTIFIER_DIR="${HOME}/.config/claude-notifier"
SESSIONS_DIR="${CLAUDE_NOTIFIER_DIR}/sessions"
DAEMON_PID_FILE="${CLAUDE_NOTIFIER_DIR}/.daemon.pid"
DAEMON_LOCK_DIR="${CLAUDE_NOTIFIER_DIR}/.daemon.lock"

write_state_file() {
  local session_id="$1"
  local state="$2"
  local command="${3:-}"
  local tool_use_id="${4:-}"

  mkdir -p "$SESSIONS_DIR"
  local state_file="${SESSIONS_DIR}/${session_id}.state"
  local now
  now=$(date +%s)

  # Preserve alerted flag if updating an existing file
  local alerted="false"
  if [[ -f "$state_file" ]]; then
    local old_alerted
    old_alerted=$(grep '^alerted=' "$state_file" 2>/dev/null | cut -d= -f2)
    # Reset alerted if command changed (new tool started)
    local old_command
    old_command=$(grep '^command=' "$state_file" 2>/dev/null | cut -d= -f2-)
    if [[ -n "$old_alerted" && "$old_command" == "$command" ]]; then
      alerted="$old_alerted"
    fi
  fi

  cat > "$state_file" << EOF
state=${state}
timestamp=${now}
kitty_window_id=${KITTY_WINDOW_ID:-}
command=${command}
tool_use_id=${tool_use_id}
alerted=${alerted}
EOF
}

read_state_file() {
  local state_file="$1"
  # Source-safe: read key=value pairs into local vars via output
  if [[ ! -f "$state_file" ]]; then
    return 1
  fi
  cat "$state_file"
}

remove_state_file() {
  local session_id="$1"
  rm -f "${SESSIONS_DIR}/${session_id}.state"
}

ensure_daemon() {
  local daemon_script="${1:-}"
  [[ -z "$daemon_script" ]] && return 0

  # Stale lock guard: if lock dir is older than 30s, remove it
  if [[ -d "$DAEMON_LOCK_DIR" ]]; then
    local lock_age
    if [[ "$(uname)" == "Darwin" ]]; then
      lock_age=$(( $(date +%s) - $(stat -f %m "$DAEMON_LOCK_DIR") ))
    else
      lock_age=$(( $(date +%s) - $(stat -c %Y "$DAEMON_LOCK_DIR") ))
    fi
    if [[ $lock_age -gt 30 ]]; then
      rmdir "$DAEMON_LOCK_DIR" 2>/dev/null || true
    fi
  fi

  # Try to acquire lock (atomic mkdir)
  if ! mkdir "$DAEMON_LOCK_DIR" 2>/dev/null; then
    return 0  # Another hook is checking, skip
  fi

  # We got the lock — check if daemon is running
  trap 'rmdir "$DAEMON_LOCK_DIR" 2>/dev/null || true' RETURN

  if [[ -f "$DAEMON_PID_FILE" ]]; then
    local daemon_pid
    daemon_pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
    if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
      return 0  # Daemon is running
    fi
    rm -f "$DAEMON_PID_FILE"  # Stale PID
  fi

  # Start daemon in background
  nohup "$daemon_script" &>/dev/null &
  echo $! > "$DAEMON_PID_FILE"
}
