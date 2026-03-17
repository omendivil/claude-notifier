# Improved State Model & Daemon — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand claude-notifier from 5 states to 8, add a background daemon for time-based idle transitions, and add stuck detection for hangable commands (npm install, dev servers, etc).

**Architecture:** Hook handler writes session state files + does immediate visual updates. Single background daemon polls state files every 10s for time-based transitions (done→idle) and stuck command alerts. jq now required at runtime.

**Tech Stack:** Bash 3.2+, jq, Kitty IPC (`kitten @`)

**Spec:** `docs/superpowers/specs/2026-03-17-improved-state-model-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/config.sh` | Modify | Add new config keys: IDLE_TIMEOUT, STUCK_TIMEOUT, STUCK_COMMANDS, COLOR_RESEARCHING, COLOR_ERROR |
| `config/default.conf` | Modify | Add new config keys with defaults |
| `lib/kitty.sh` | Modify | Add `kitty_set_tab_color_by_id()` and `kitty_set_tab_title_by_id()` for daemon use |
| `lib/color.sh` | Modify | Add researching, error, waiting, idle cases to `set_state_color()` |
| `lib/blink.sh` | Modify | Add error (2 fast blinks), researching (1 flash), waiting (no blink), idle (1 slow pulse) patterns |
| `lib/notify.sh` | Modify | Add error notification, rename done/idle to done, add waiting (no notify) |
| `lib/state.sh` | Create | State file read/write functions + `ensure_daemon()` |
| `lib/stuck.sh` | Create | `is_stuck_command()` matcher + `format_elapsed()` for title |
| `bin/claude-notifier` | Modify | Add --stdin/--cleanup flags, new states, state file writes, split debounce from state writes |
| `bin/claude-notifier-daemon` | Create | Background daemon: poll sessions/, idle transitions, stuck detection |
| `tests/test-all.sh` | Modify | Update existing tests for new states + add new tests |
| `install.sh` | Modify | Register new hooks, install daemon script, create sessions/ dir |
| `uninstall.sh` | Modify | Kill daemon, remove sessions/, PID file, state files |

---

### Task 1: Config — Add New Keys

**Files:**
- Modify: `lib/config.sh:8-17` (defaults) and `lib/config.sh:43-61` (validation)
- Modify: `config/default.conf`
- Test: `tests/test-all.sh`

- [ ] **Step 1: Update defaults in lib/config.sh**

Add after line 17 (`DEBOUNCE_WORKING=3`):

```bash
COLOR_RESEARCHING="#007aff"
COLOR_ERROR="#ff6b00"
IDLE_TIMEOUT=300
STUCK_TIMEOUT=180
STUCK_COMMANDS="install|init|create-|run dev|run start|serve"
```

- [ ] **Step 2: Update validation in lib/config.sh**

In the `case "$key"` block, update the color validation (line 50) to include new colors:

```bash
COLOR_PERMISSION|COLOR_DONE|COLOR_WORKING|COLOR_RESEARCHING|COLOR_ERROR)
```

Update the number validation (line 56) to include new timeout keys:

```bash
BLINK_FAST|BLINK_SLOW|DEBOUNCE_WORKING|IDLE_TIMEOUT|STUCK_TIMEOUT)
```

Add a new case for STUCK_COMMANDS before the `*` catch-all (line 62):

```bash
STUCK_COMMANDS)
  if ! [[ "$value" =~ ^[a-zA-Z0-9\ \|\-]+$ ]]; then
    echo "claude-notifier: invalid pattern for $key: $value" >&2
    continue
  fi
  ;;
```

- [ ] **Step 3: Update config/default.conf**

Add after the `DEBOUNCE_WORKING=3` line:

```bash

# ── State Colors (additional) ─────────────────
COLOR_RESEARCHING="#007aff"
COLOR_ERROR="#ff6b00"

# ── Daemon Settings ───────────────────────────
# Seconds before done/waiting → idle (daemon checks every 10s)
IDLE_TIMEOUT=300
# Seconds before alerting on watched commands
STUCK_TIMEOUT=180
# Pipe-delimited patterns for commands that can hang
STUCK_COMMANDS="install|init|create-|run dev|run start|serve"
```

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `bash tests/test-all.sh`
Expected: All 10 tests pass (new config keys have defaults, existing behavior unchanged)

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh config/default.conf
git commit -m "feat: add config keys for daemon, stuck detection, and new state colors"
```

---

### Task 2: Kitty Helpers — Add by-ID Functions

**Files:**
- Modify: `lib/kitty.sh`
- Test: `tests/test-all.sh`

- [ ] **Step 1: Add by-ID functions to lib/kitty.sh**

Append after `kitty_notify()` (line 23):

```bash

# ── Daemon helpers (target by window ID, not --self) ──
kitty_set_tab_color_by_id() {
  local window_id="$1"; shift
  kitten @ set-tab-color --match "id:${window_id}" "$@" 2>/dev/null
}

kitty_set_tab_title_by_id() {
  local window_id="$1"; shift
  kitten @ set-tab-title --match "id:${window_id}" "$@" 2>/dev/null
}
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass (new functions aren't called yet)

- [ ] **Step 3: Commit**

```bash
git add lib/kitty.sh
git commit -m "feat: add kitty by-ID helper functions for daemon tab targeting"
```

---

### Task 3: Color — Add New States

**Files:**
- Modify: `lib/color.sh:10-23`

- [ ] **Step 1: Update set_state_color() case statement**

Replace the entire case block (lines 10-23) with:

```bash
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
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add lib/color.sh
git commit -m "feat: add researching, error, waiting, idle color states"
```

---

### Task 4: Blink — Add New State Patterns

**Files:**
- Modify: `lib/blink.sh:25-47`

- [ ] **Step 1: Update _do_blink() case statement**

Replace the case block (lines 25-47) with:

```bash
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
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass (tests 1-3 still work, new states handled)

- [ ] **Step 3: Commit**

```bash
git add lib/blink.sh
git commit -m "feat: add distinct blink patterns for error, idle, researching states"
```

---

### Task 5: Notify — Add Error + Update State Names

**Files:**
- Modify: `lib/notify.sh:25-38`

- [ ] **Step 1: Update send_notification() case statement**

Replace the case block (lines 25-38) with:

```bash
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
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add lib/notify.sh
git commit -m "feat: add error desktop notification, update state handling"
```

---

### Task 6: State File Library (New)

**Files:**
- Create: `lib/state.sh`
- Test: `tests/test-all.sh`

- [ ] **Step 1: Write test for state file write/read**

Add to `tests/test-all.sh` before the cleanup section (line 161):

```bash
# ── Test 11: State file write and read ────────
echo "Test 11: State file write and read"
export KITTY_WINDOW_ID="12345"
SESSIONS_DIR="${TMPDIR_TEST}/.config/claude-notifier/sessions"
mkdir -p "$SESSIONS_DIR"
source "${PROJECT_DIR}/lib/state.sh"
write_state_file "test-session-1" "working" "npm install" "toolu_abc"
if [[ -f "${SESSIONS_DIR}/test-session-1.state" ]]; then
  echo "  PASS: state file created"
  ((PASS++)) || true
else
  echo "  FAIL: state file not created"
  ((FAIL++)) || true
fi
state_content=$(cat "${SESSIONS_DIR}/test-session-1.state")
if echo "$state_content" | grep -q "state=working"; then
  echo "  PASS: state file contains correct state"
  ((PASS++)) || true
else
  echo "  FAIL: state file missing state=working"
  ((FAIL++)) || true
fi
if echo "$state_content" | grep -q "kitty_window_id=12345"; then
  echo "  PASS: state file contains window ID"
  ((PASS++)) || true
else
  echo "  FAIL: state file missing kitty_window_id"
  ((FAIL++)) || true
fi
rm -f "${SESSIONS_DIR}/test-session-1.state"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-all.sh`
Expected: FAIL — `lib/state.sh` doesn't exist yet

- [ ] **Step 3: Create lib/state.sh**

```bash
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
  trap 'rmdir "$DAEMON_LOCK_DIR" 2>/dev/null' RETURN

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-all.sh`
Expected: All tests pass including new test 11

- [ ] **Step 5: Write test for ensure_daemon**

Add to `tests/test-all.sh`:

```bash
# ── Test 12: ensure_daemon starts daemon ──────
echo "Test 12: ensure_daemon starts a daemon process"
# Create a simple daemon script that writes a marker file
MOCK_DAEMON="${TMPDIR_TEST}/mock-daemon"
DAEMON_MARKER="${TMPDIR_TEST}/daemon-started"
cat > "$MOCK_DAEMON" << 'DEOF'
#!/usr/bin/env bash
touch "$1"
sleep 10
DEOF
chmod +x "$MOCK_DAEMON"
# Patch the daemon to write marker
cat > "$MOCK_DAEMON" << DEOF
#!/usr/bin/env bash
touch "${DAEMON_MARKER}"
sleep 10
DEOF
chmod +x "$MOCK_DAEMON"
rm -f "$DAEMON_MARKER"
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.daemon.pid"
rm -rf "${TMPDIR_TEST}/.config/claude-notifier/.daemon.lock"
ensure_daemon "$MOCK_DAEMON"
sleep 0.5
if [[ -f "$DAEMON_MARKER" ]]; then
  echo "  PASS: daemon was started"
  ((PASS++)) || true
else
  echo "  FAIL: daemon was not started"
  ((FAIL++)) || true
fi
# Clean up daemon
if [[ -f "${TMPDIR_TEST}/.config/claude-notifier/.daemon.pid" ]]; then
  kill "$(cat "${TMPDIR_TEST}/.config/claude-notifier/.daemon.pid")" 2>/dev/null || true
fi
```

- [ ] **Step 6: Run tests**

Run: `bash tests/test-all.sh`
Expected: All 12+ tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/state.sh tests/test-all.sh
git commit -m "feat: add state file library with session tracking and daemon lifecycle"
```

---

### Task 7: Stuck Detection Library (New)

**Files:**
- Create: `lib/stuck.sh`
- Test: `tests/test-all.sh`

- [ ] **Step 1: Write test for stuck command matching**

Add to `tests/test-all.sh`:

```bash
# ── Test 13: Stuck command matching ───────────
echo "Test 13: Stuck command matching"
source "${PROJECT_DIR}/lib/stuck.sh"
# Should match
if is_stuck_command "npm install react" "install|init|create-|run dev|run start|serve"; then
  echo "  PASS: npm install matched"
  ((PASS++)) || true
else
  echo "  FAIL: npm install should match"
  ((FAIL++)) || true
fi
if is_stuck_command "yarn run dev --port 3000" "install|init|create-|run dev|run start|serve"; then
  echo "  PASS: yarn run dev matched"
  ((PASS++)) || true
else
  echo "  FAIL: yarn run dev should match"
  ((FAIL++)) || true
fi
# Should NOT match
if is_stuck_command "npm run build" "install|init|create-|run dev|run start|serve"; then
  echo "  FAIL: npm run build should NOT match"
  ((FAIL++)) || true
else
  echo "  PASS: npm run build not matched"
  ((PASS++)) || true
fi
if is_stuck_command "echo install something" "install|init|create-|run dev|run start|serve"; then
  echo "  FAIL: echo install should NOT match"
  ((FAIL++)) || true
else
  echo "  PASS: echo install not matched"
  ((PASS++)) || true
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-all.sh`
Expected: FAIL — `lib/stuck.sh` doesn't exist yet

- [ ] **Step 3: Create lib/stuck.sh**

```bash
#!/usr/bin/env bash
# Stuck command detection: matching and elapsed time formatting

is_stuck_command() {
  local command="$1"
  local patterns="$2"

  [[ -z "$command" || -z "$patterns" ]] && return 1

  # Tokenize the command
  local -a tokens
  read -ra tokens <<< "$command"
  local num_tokens=${#tokens[@]}

  # Check each pattern (pipe-delimited)
  local IFS='|'
  local -a pattern_list
  read -ra pattern_list <<< "$patterns"

  for pattern in "${pattern_list[@]}"; do
    # Count words in pattern
    local -a pattern_words
    read -ra pattern_words <<< "$pattern"
    local pattern_len=${#pattern_words[@]}

    if [[ $pattern_len -eq 1 ]]; then
      # Single-word pattern: match against tokens at position 1+ (skip the binary name)
      # Also handle prefix patterns (ending with -)
      for (( i=1; i<num_tokens; i++ )); do
        if [[ "$pattern" == *- ]]; then
          # Prefix match: "create-" matches "create-react-app"
          if [[ "${tokens[$i]}" == ${pattern}* ]]; then
            return 0
          fi
        else
          if [[ "${tokens[$i]}" == "$pattern" ]]; then
            return 0
          fi
        fi
      done
    else
      # Multi-word pattern: match consecutive tokens at position 1+
      for (( i=1; i<=num_tokens-pattern_len; i++ )); do
        local match=true
        for (( j=0; j<pattern_len; j++ )); do
          if [[ "${tokens[$((i+j))]}" != "${pattern_words[$j]}" ]]; then
            match=false
            break
          fi
        done
        if [[ "$match" == "true" ]]; then
          return 0
        fi
      done
    fi
  done

  return 1
}

format_elapsed() {
  local seconds="$1"
  if [[ $seconds -ge 3600 ]]; then
    echo "$((seconds / 3600))h"
  elif [[ $seconds -ge 60 ]]; then
    echo "$((seconds / 60))m"
  else
    echo "${seconds}s"
  fi
}

extract_command_keyword() {
  # Extract short keyword for tab title from a full command
  # "npm install react" → "npm"
  # "/usr/bin/npm install" → "npm"
  local command="$1"
  local -a tokens
  read -ra tokens <<< "$command"
  local binary="${tokens[0]}"
  # Strip path prefix
  basename "$binary"
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass including test 13

- [ ] **Step 5: Write test for format_elapsed**

Add to `tests/test-all.sh`:

```bash
# ── Test 14: Elapsed time formatting ──────────
echo "Test 14: Elapsed time formatting"
result=$(format_elapsed 30)
if [[ "$result" == "30s" ]]; then
  echo "  PASS: 30s formatted"
  ((PASS++)) || true
else
  echo "  FAIL: expected 30s, got $result"
  ((FAIL++)) || true
fi
result=$(format_elapsed 180)
if [[ "$result" == "3m" ]]; then
  echo "  PASS: 3m formatted"
  ((PASS++)) || true
else
  echo "  FAIL: expected 3m, got $result"
  ((FAIL++)) || true
fi
result=$(format_elapsed 7200)
if [[ "$result" == "2h" ]]; then
  echo "  PASS: 2h formatted"
  ((PASS++)) || true
else
  echo "  FAIL: expected 2h, got $result"
  ((FAIL++)) || true
fi
```

- [ ] **Step 6: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/stuck.sh tests/test-all.sh
git commit -m "feat: add stuck command detection with token matching and elapsed formatting"
```

---

### Task 8: Main Dispatcher — Enhance bin/claude-notifier

**Files:**
- Modify: `bin/claude-notifier`
- Test: `tests/test-all.sh`

- [ ] **Step 1: Write test for new states being accepted**

Add to `tests/test-all.sh`:

```bash
# ── Test 15: New states accepted ──────────────
echo "Test 15: New states accepted (researching, error, waiting)"
export KITTY_WINDOW_ID="12345"
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
for new_state in researching error waiting; do
  > "$MOCK_LOG"
  echo '{"session_id":"test-123"}' | "$NOTIFIER" --state "$new_state" --stdin
  sleep 0.3
  if grep -q "set-tab-title" "$MOCK_LOG" 2>/dev/null; then
    echo "  PASS: $new_state state accepted"
    ((PASS++)) || true
  else
    echo "  FAIL: $new_state state not accepted"
    ((FAIL++)) || true
  fi
done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-all.sh`
Expected: FAIL — new states not yet accepted, --stdin not yet recognized

- [ ] **Step 3: Update bin/claude-notifier**

Full replacement of `bin/claude-notifier`:

```bash
#!/usr/bin/env bash
# Claude Notifier v2.0.0 — main dispatcher
# Called by Claude Code hooks to signal state changes to Kitty tabs
#
# Usage: claude-notifier --state <state> [--stdin]
#        claude-notifier --cleanup --stdin
#        claude-notifier --test
#        claude-notifier --version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
CLAUDE_NOTIFIER_DIR="${HOME}/.config/claude-notifier"

# ── Parse arguments ──────────────────────────────
STATE=""
READ_STDIN=false
CLEANUP_MODE=false
TEST_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      [[ $# -lt 2 ]] && { echo "claude-notifier: --state requires a value" >&2; exit 1; }
      STATE="$2"
      shift 2
      ;;
    --stdin)
      READ_STDIN=true
      shift
      ;;
    --cleanup)
      CLEANUP_MODE=true
      shift
      ;;
    --test)
      TEST_MODE=true
      shift
      ;;
    --version)
      echo "claude-notifier 2.0.0"
      exit 0
      ;;
    --help|-h)
      echo "Usage: claude-notifier --state <state> [--stdin]"
      echo "       claude-notifier --cleanup --stdin"
      echo "       claude-notifier --test    Run a test blink"
      echo "       claude-notifier --version Show version"
      echo ""
      echo "States: working, permission, researching, error, done, waiting, idle, normal"
      exit 0
      ;;
    *)
      echo "claude-notifier: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Test mode ────────────────────────────────────
if [[ "$TEST_MODE" == "true" ]]; then
  source "${LIB_DIR}/config.sh"
  load_config
  source "${LIB_DIR}/blink.sh"
  echo "claude-notifier: sending test blink..."
  run_blink "permission"
  sleep 1
  echo "claude-notifier: test complete"
  exit 0
fi

# ── Read stdin JSON ──────────────────────────────
STDIN_JSON=""
if [[ "$READ_STDIN" == "true" && ! -t 0 ]]; then
  STDIN_JSON=$(cat)
elif [[ ! -t 0 ]]; then
  # Backwards compat: read stdin even without --stdin flag
  STDIN_JSON=$(cat)
fi

# ── Extract fields from JSON ─────────────────────
SESSION_ID=""
TOOL_NAME=""
TOOL_COMMAND=""
TOOL_USE_ID=""
if [[ -n "$STDIN_JSON" ]] && command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null || true)
  TOOL_NAME=$(echo "$STDIN_JSON" | jq -r '.tool_name // empty' 2>/dev/null || true)
  TOOL_COMMAND=$(echo "$STDIN_JSON" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  TOOL_USE_ID=$(echo "$STDIN_JSON" | jq -r '.tool_use_id // empty' 2>/dev/null || true)
fi

# ── Cleanup mode ─────────────────────────────────
if [[ "$CLEANUP_MODE" == "true" ]]; then
  source "${LIB_DIR}/kitty.sh"
  kitty_set_tab_title ""
  kitty_set_tab_color active_bg=NONE
  if [[ -n "$SESSION_ID" ]]; then
    source "${LIB_DIR}/state.sh"
    remove_state_file "$SESSION_ID"
  fi
  exit 0
fi

# ── Validate state ───────────────────────────────
if [[ -z "$STATE" ]]; then
  echo "claude-notifier: --state is required" >&2
  exit 1
fi

case "$STATE" in
  permission|done|waiting|idle|working|researching|error|normal) ;;
  *)
    echo "claude-notifier: unknown state: $STATE" >&2
    exit 1
    ;;
esac

# ── Load config ──────────────────────────────────
source "${LIB_DIR}/config.sh"
load_config

# ── Write state file (always, regardless of debounce) ──
if [[ -n "$SESSION_ID" ]]; then
  source "${LIB_DIR}/state.sh"
  # For working state with a Bash tool, pass the command for stuck detection
  local_command=""
  local_tool_id=""
  if [[ "$STATE" == "working" && "$TOOL_NAME" == "Bash" ]]; then
    local_command="$TOOL_COMMAND"
    local_tool_id="$TOOL_USE_ID"
  fi
  write_state_file "$SESSION_ID" "$STATE" "$local_command" "$local_tool_id"

  # Ensure daemon is running
  DAEMON_SCRIPT="${SCRIPT_DIR}/claude-notifier-daemon"
  if [[ -x "$DAEMON_SCRIPT" ]]; then
    ensure_daemon "$DAEMON_SCRIPT"
  fi
fi

# ── Debounce visual updates (working state only) ──
if [[ "$STATE" == "working" ]]; then
  mkdir -p "$CLAUDE_NOTIFIER_DIR"
  DEBOUNCE_FILE="${CLAUDE_NOTIFIER_DIR}/.last-working-notify"
  now=$(date +%s)
  debounce_sec="${DEBOUNCE_WORKING:-3}"
  debounce_sec="${debounce_sec%%.*}"
  if [[ -f "$DEBOUNCE_FILE" ]]; then
    last_notify=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
    elapsed=$((now - last_notify))
    if [[ $elapsed -lt $debounce_sec ]]; then
      exit 0
    fi
  fi
  echo "$now" > "$DEBOUNCE_FILE"
fi

# ── Set tab title ────────────────────────────────
source "${LIB_DIR}/kitty.sh"
case "$STATE" in
  permission)   kitty_set_tab_title "⛔ Perm" ;;
  done)         kitty_set_tab_title "✅ Done" ;;
  waiting)      kitty_set_tab_title "⏳ Wait" ;;
  idle)         kitty_set_tab_title "💤 Idle" ;;
  working)      kitty_set_tab_title "⚡ Work" ;;
  researching)  kitty_set_tab_title "🔍 Research" ;;
  error)        kitty_set_tab_title "❌ Error" ;;
  normal)       kitty_set_tab_title "" ;;
esac

# ── Dispatch to enabled modes ────────────────────
if [[ "${NOTIFY_BLINK:-true}" == "true" ]]; then
  source "${LIB_DIR}/blink.sh"
  run_blink "$STATE"
fi

if [[ "${NOTIFY_COLOR:-false}" == "true" ]]; then
  source "${LIB_DIR}/color.sh"
  set_state_color "$STATE"
fi

if [[ "${NOTIFY_DESKTOP:-false}" == "true" ]]; then
  source "${LIB_DIR}/notify.sh"
  send_notification "$STATE" "$STDIN_JSON"
fi
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test-all.sh`
Expected: Tests 1-10 may need adjustment (version changed to 2.0.0, title strings shortened). Update test 8 for new version and test 5 for new color behavior.

- [ ] **Step 5: Update existing tests for v2 changes**

Update test 8 (version check) to expect `2.0.0`:

```bash
if [[ "$version_output" == "claude-notifier 2.0.0" ]]; then
```

Update test 5 (color check) — the color key is now `#ff003c` from `default.conf` (not `#ff9500` from old hardcoded defaults):

```bash
assert_contains "sets red color" "#ff003c" "$MOCK_LOG"
```

Also add `sessions` directory to test setup (line 31):

```bash
mkdir -p "${TMPDIR_TEST}/.config/claude-notifier/sessions"
```

Also create a mock `jq` if needed, or ensure the real `jq` is available in test env.

- [ ] **Step 6: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add bin/claude-notifier tests/test-all.sh
git commit -m "feat: enhance dispatcher with stdin JSON parsing, state files, new states"
```

---

### Task 9: Daemon (New)

**Files:**
- Create: `bin/claude-notifier-daemon`
- Test: `tests/test-all.sh`

- [ ] **Step 1: Write test for daemon idle transition**

Add to `tests/test-all.sh`:

```bash
# ── Test 16: Daemon idle transition ───────────
echo "Test 16: Daemon transitions done → idle after timeout"
export KITTY_WINDOW_ID="12345"
SESSIONS_DIR="${TMPDIR_TEST}/.config/claude-notifier/sessions"
mkdir -p "$SESSIONS_DIR"
> "$MOCK_LOG"
# Write a state file with old timestamp (simulate 10 minutes ago)
old_ts=$(( $(date +%s) - 600 ))
cat > "${SESSIONS_DIR}/daemon-test-1.state" << EOF
state=done
timestamp=${old_ts}
kitty_window_id=12345
command=
tool_use_id=
alerted=false
EOF
# Run one daemon cycle
IDLE_TIMEOUT=2
STUCK_TIMEOUT=999
STUCK_COMMANDS="install"
source "${PROJECT_DIR}/lib/state.sh"
source "${PROJECT_DIR}/lib/stuck.sh"
source "${PROJECT_DIR}/lib/kitty.sh"
source "${PROJECT_DIR}/lib/blink.sh"
source "${PROJECT_DIR}/lib/config.sh"
# Source the daemon's poll function directly
source "${PROJECT_DIR}/bin/claude-notifier-daemon" --test-poll
sleep 1
# Check state file was updated to idle
if grep -q "state=idle" "${SESSIONS_DIR}/daemon-test-1.state" 2>/dev/null; then
  echo "  PASS: state transitioned to idle"
  ((PASS++)) || true
else
  echo "  FAIL: state not transitioned to idle"
  ((FAIL++)) || true
fi
if grep -q "set-tab-title" "$MOCK_LOG" 2>/dev/null; then
  echo "  PASS: tab title was updated"
  ((PASS++)) || true
else
  echo "  FAIL: tab title not updated"
  ((FAIL++)) || true
fi
rm -f "${SESSIONS_DIR}/daemon-test-1.state"
```

- [ ] **Step 2: Create bin/claude-notifier-daemon**

```bash
#!/usr/bin/env bash
# Claude Notifier Daemon v2.0.0
# Single background process that monitors all session state files
# for time-based transitions (done→idle) and stuck command detection.
#
# Started by ensure_daemon() in lib/state.sh. Auto-stops when no sessions remain.
# Can be sourced with --test-poll to expose poll_sessions() for testing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
CLAUDE_NOTIFIER_DIR="${HOME}/.config/claude-notifier"
SESSIONS_DIR="${CLAUDE_NOTIFIER_DIR}/sessions"
DAEMON_PID_FILE="${CLAUDE_NOTIFIER_DIR}/.daemon.pid"
POLL_INTERVAL=10
EMPTY_POLLS=0
MAX_EMPTY_POLLS=30  # 30 * 10s = 5 min before auto-stop

source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/kitty.sh"
source "${LIB_DIR}/stuck.sh"

poll_sessions() {
  load_config
  local now
  now=$(date +%s)
  local found_sessions=false

  for state_file in "${SESSIONS_DIR}"/*.state; do
    [[ -f "$state_file" ]] || continue
    found_sessions=true

    # Read state file fields
    local state="" timestamp="" kitty_window_id="" command="" tool_use_id="" alerted=""
    while IFS='=' read -r key value; do
      case "$key" in
        state) state="$value" ;;
        timestamp) timestamp="$value" ;;
        kitty_window_id) kitty_window_id="$value" ;;
        command) command="$value" ;;
        tool_use_id) tool_use_id="$value" ;;
        alerted) alerted="$value" ;;
      esac
    done < "$state_file"

    [[ -z "$timestamp" ]] && continue
    local elapsed=$(( now - timestamp ))

    # Dead session cleanup (1 hour)
    if [[ $elapsed -gt 3600 ]]; then
      rm -f "$state_file"
      continue
    fi

    # Idle transition: done|waiting → idle after IDLE_TIMEOUT
    local idle_timeout="${IDLE_TIMEOUT:-300}"
    idle_timeout="${idle_timeout%%.*}"
    if [[ "$state" == "done" || "$state" == "waiting" ]] && [[ $elapsed -gt $idle_timeout ]]; then
      if [[ -n "$kitty_window_id" ]]; then
        # Blink reminder
        kitty_set_tab_color_by_id "$kitty_window_id" active_bg="#ffffff"
        sleep 0.3
        kitty_set_tab_color_by_id "$kitty_window_id" active_bg=NONE
        # Set idle state
        kitty_set_tab_title_by_id "$kitty_window_id" "💤 Idle"
        kitty_set_tab_color_by_id "$kitty_window_id" active_bg=NONE
      fi
      # Update state file
      sed -i '' "s/^state=.*/state=idle/" "$state_file" 2>/dev/null || \
        sed -i "s/^state=.*/state=idle/" "$state_file" 2>/dev/null
      continue
    fi

    # Stuck detection: working state with a watched command
    local stuck_timeout="${STUCK_TIMEOUT:-180}"
    stuck_timeout="${stuck_timeout%%.*}"
    local stuck_commands="${STUCK_COMMANDS:-install|init|create-|run dev|run start|serve}"
    if [[ "$state" == "working" && -n "$command" ]] && \
       [[ $elapsed -gt $stuck_timeout ]] && \
       is_stuck_command "$command" "$stuck_commands"; then

      local keyword
      keyword=$(extract_command_keyword "$command")
      local elapsed_fmt
      elapsed_fmt=$(format_elapsed "$elapsed")

      # Update title with elapsed time
      if [[ -n "$kitty_window_id" ]]; then
        kitty_set_tab_title_by_id "$kitty_window_id" "⏰ ${keyword} ${elapsed_fmt}"
      fi

      # Send desktop notification (once)
      if [[ "$alerted" != "true" ]]; then
        kitten notify --title "Claude Code" "${keyword} has been running for ${elapsed_fmt}" 2>/dev/null || true
        sed -i '' "s/^alerted=.*/alerted=true/" "$state_file" 2>/dev/null || \
          sed -i "s/^alerted=.*/alerted=true/" "$state_file" 2>/dev/null
      fi
    fi
  done

  # Auto-stop tracking
  if [[ "$found_sessions" == "false" ]]; then
    ((EMPTY_POLLS++)) || true
  else
    EMPTY_POLLS=0
  fi
}

# ── Test mode: expose poll_sessions for testing ──
if [[ "${1:-}" == "--test-poll" ]]; then
  poll_sessions
  return 0 2>/dev/null || exit 0
fi

# ── Main daemon loop ─────────────────────────────
trap 'rm -f "$DAEMON_PID_FILE"; exit 0' SIGTERM SIGINT
echo $$ > "$DAEMON_PID_FILE"

while true; do
  poll_sessions

  if [[ $EMPTY_POLLS -ge $MAX_EMPTY_POLLS ]]; then
    rm -f "$DAEMON_PID_FILE"
    exit 0
  fi

  sleep "$POLL_INTERVAL"
done
```

- [ ] **Step 3: Make daemon executable**

```bash
chmod +x bin/claude-notifier-daemon
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass including test 16

- [ ] **Step 5: Write test for stuck detection**

Add to `tests/test-all.sh`:

```bash
# ── Test 17: Daemon stuck detection ───────────
echo "Test 17: Daemon detects stuck command"
> "$MOCK_LOG"
old_ts=$(( $(date +%s) - 300 ))
cat > "${SESSIONS_DIR}/daemon-test-2.state" << EOF
state=working
timestamp=${old_ts}
kitty_window_id=12345
command=npm install react
tool_use_id=toolu_abc
alerted=false
EOF
IDLE_TIMEOUT=999
STUCK_TIMEOUT=2
source "${PROJECT_DIR}/bin/claude-notifier-daemon" --test-poll
sleep 0.5
if grep -q "set-tab-title.*npm" "$MOCK_LOG" 2>/dev/null; then
  echo "  PASS: stuck title updated"
  ((PASS++)) || true
else
  echo "  FAIL: stuck title not updated"
  ((FAIL++)) || true
fi
if grep -q "alerted=true" "${SESSIONS_DIR}/daemon-test-2.state" 2>/dev/null; then
  echo "  PASS: alerted flag set"
  ((PASS++)) || true
else
  echo "  FAIL: alerted flag not set"
  ((FAIL++)) || true
fi
rm -f "${SESSIONS_DIR}/daemon-test-2.state"
```

- [ ] **Step 6: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add bin/claude-notifier-daemon tests/test-all.sh
git commit -m "feat: add background daemon for idle transitions and stuck detection"
```

---

### Task 10: Install/Uninstall Updates

**Files:**
- Modify: `install.sh`
- Modify: `uninstall.sh`

- [ ] **Step 1: Update install.sh — add jq runtime check, daemon install, sessions dir**

In Step 2 (copy files section, around line 48-57), add after `chmod +x`:

```bash
cp "${SCRIPT_DIR}/bin/claude-notifier-daemon" "${INSTALL_DIR}/bin/"
chmod +x "${INSTALL_DIR}/bin/claude-notifier-daemon"
mkdir -p "${INSTALL_DIR}/sessions"
```

- [ ] **Step 2: Update install.sh — update hooks JSON**

Replace the HOOKS_JSON block (lines 63-74) with the new hook configuration:

```bash
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
```

Also update the merge logic to handle all new hook event types (add `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `SubagentStart`, `SubagentStop`, `SessionEnd` to the jq merge).

- [ ] **Step 3: Update uninstall.sh — kill daemon, clean sessions**

Add after the hook removal section (around line 58), before file removal:

```bash
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
```

In the file removal section, add session cleanup:

```bash
rm -rf "${INSTALL_DIR}/sessions"
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add install.sh uninstall.sh
git commit -m "feat: update installer for v2 hooks, daemon, and session management"
```

---

### Task 11: Integration Test + Final Verification

**Files:**
- Modify: `tests/test-all.sh` (add integration test)

- [ ] **Step 1: Add end-to-end state lifecycle test**

```bash
# ── Test 18: Full state lifecycle ─────────────
echo "Test 18: Full state lifecycle (working → permission → working → done)"
export KITTY_WINDOW_ID="12345"
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
SESSIONS_DIR="${TMPDIR_TEST}/.config/claude-notifier/sessions"
mkdir -p "$SESSIONS_DIR"
> "$MOCK_LOG"

# Simulate: user submits prompt
echo '{"session_id":"lifecycle-1"}' | "$NOTIFIER" --state working --stdin
sleep 0.3

# Simulate: permission needed
echo '{"session_id":"lifecycle-1","message":"Claude needs permission to use Bash"}' | "$NOTIFIER" --state permission --stdin
sleep 0.3

# Simulate: tool approved and completed
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
echo '{"session_id":"lifecycle-1","tool_name":"Bash"}' | "$NOTIFIER" --state working --stdin
sleep 0.3

# Simulate: Claude finishes
echo '{"session_id":"lifecycle-1"}' | "$NOTIFIER" --state done --stdin
sleep 0.3

# Verify state file exists with done state
if grep -q "state=done" "${SESSIONS_DIR}/lifecycle-1.state" 2>/dev/null; then
  echo "  PASS: lifecycle ended in done state"
  ((PASS++)) || true
else
  echo "  FAIL: lifecycle did not end in done state"
  ((FAIL++)) || true
fi

# Simulate: cleanup
echo '{"session_id":"lifecycle-1"}' | "$NOTIFIER" --cleanup --stdin

if [[ ! -f "${SESSIONS_DIR}/lifecycle-1.state" ]]; then
  echo "  PASS: state file cleaned up"
  ((PASS++)) || true
else
  echo "  FAIL: state file not cleaned up"
  ((FAIL++)) || true
fi
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/test-all.sh`
Expected: All tests pass

- [ ] **Step 3: Run shellcheck on all scripts**

Run: `shellcheck bin/claude-notifier bin/claude-notifier-daemon lib/*.sh`
Expected: No errors (warnings about `local` in global scope may appear — acceptable for bash)

- [ ] **Step 4: Fix any shellcheck issues**

Address any errors found. Common bash issues: quoting, unused variables, unreachable code.

- [ ] **Step 5: Final commit**

```bash
git add tests/test-all.sh
git commit -m "test: add integration tests for full state lifecycle"
```

- [ ] **Step 6: Push branch and create PR**

```bash
git push -u origin feat/improved-state-model
gh pr create --title "feat: improved state model with daemon and stuck detection" --body "$(cat <<'EOF'
## Summary
- Expand from 5 to 8 states: add researching, error, waiting; rename idle semantics
- Add background daemon for time-based idle transitions (done → idle after 5 min)
- Add stuck detection for hangable commands (npm install, dev servers)
- jq now required at runtime for JSON parsing from hook stdin
- Version bump to 2.0.0

## Changes
- `bin/claude-notifier` — enhanced with --stdin, --cleanup, new states, state file writes
- `bin/claude-notifier-daemon` — new background process for time-based transitions
- `lib/state.sh` — new state file management and daemon lifecycle
- `lib/stuck.sh` — new stuck command matching and elapsed formatting
- `lib/config.sh` — new config keys for daemon, stuck detection, colors
- `lib/color.sh`, `lib/blink.sh`, `lib/notify.sh` — new state support
- `install.sh`, `uninstall.sh` — updated for new hooks and daemon

## Test plan
- [ ] All existing tests updated and passing
- [ ] New tests for state files, daemon idle transition, stuck detection, lifecycle
- [ ] Shellcheck clean
- [ ] Manual test: run Claude Code, verify state transitions in Kitty tab

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr merge --auto --squash
```

