#!/usr/bin/env bash
# Automated tests for claude-notifier using a mock kitten command
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"

# ── Setup ────────────────────────────────────────
TMPDIR_TEST=$(mktemp -d)
MOCK_LOG="${TMPDIR_TEST}/kitten_calls.log"
MOCK_KITTEN="${TMPDIR_TEST}/kitten"
FAKE_CONFIG_DIR="${TMPDIR_TEST}/config"
FAKE_CLAUDE_DIR="${TMPDIR_TEST}/claude-config"

mkdir -p "$FAKE_CONFIG_DIR" "$FAKE_CLAUDE_DIR"

# Create mock kitten that logs calls
cat > "$MOCK_KITTEN" << 'MOCKEOF'
#!/usr/bin/env bash
echo "kitten $*" >> "${MOCK_LOG}"
MOCKEOF
chmod +x "$MOCK_KITTEN"

# Put mock kitten first on PATH
export PATH="${TMPDIR_TEST}:${PATH}"
export MOCK_LOG
export HOME="$TMPDIR_TEST"
export KITTY_WINDOW_ID="12345"

# Create config directory structure
mkdir -p "${TMPDIR_TEST}/.config/claude-notifier/bin"
mkdir -p "${TMPDIR_TEST}/.config/claude-notifier/lib"
cp "${PROJECT_DIR}/config/default.conf" "${TMPDIR_TEST}/.config/claude-notifier/config.conf"
cp "${PROJECT_DIR}/lib/"*.sh "${TMPDIR_TEST}/.config/claude-notifier/lib/"
cp "${PROJECT_DIR}/bin/claude-notifier" "${TMPDIR_TEST}/.config/claude-notifier/bin/"

NOTIFIER="${TMPDIR_TEST}/.config/claude-notifier/bin/claude-notifier"

PASS=0
FAIL=0

assert_contains() {
  local label="$1"
  local expected="$2"
  local file="$3"
  if grep -q -- "$expected" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    ((PASS++)) || true
  else
    echo "  FAIL: $label (expected '$expected' in log)"
    ((FAIL++)) || true
  fi
}

assert_not_contains() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if ! grep -q -- "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    ((PASS++)) || true
  else
    echo "  FAIL: $label (unexpected '$pattern' found in log)"
    ((FAIL++)) || true
  fi
}

# ── Test 1: Blink mode (permission) ─────────────
echo "Test 1: Blink mode — permission state"
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state permission
sleep 1.5
assert_contains "calls set-tab-color" "set-tab-color" "$MOCK_LOG"
assert_contains "uses --self" "--self" "$MOCK_LOG"
assert_contains "sets active_bg" "active_bg=" "$MOCK_LOG"
assert_contains "resets to NONE" "NONE" "$MOCK_LOG"

# ── Test 2: Blink mode (done) ───────────────────
echo "Test 2: Blink mode — done state"
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state done
sleep 1.5
assert_contains "calls set-tab-color" "set-tab-color" "$MOCK_LOG"

# ── Test 3: Blink mode (working) ────────────────
echo "Test 3: Blink mode — working state"
# Reset debounce
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state working
sleep 0.5
assert_contains "calls set-tab-color for working" "set-tab-color" "$MOCK_LOG"

# ── Test 4: Debounce (working fires twice) ──────
echo "Test 4: Debounce — second working call within 3s is skipped"
# Refresh the debounce timestamp to "now" so the debounce window is still active
date +%s > "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state working
sleep 0.3
assert_not_contains "no kitten calls (debounced)" "set-tab-color" "$MOCK_LOG"

# ── Test 5: Color mode ──────────────────────────
echo "Test 5: Color mode — permission state"
# Enable color mode in config
sed -i '.bak' 's/NOTIFY_COLOR=false/NOTIFY_COLOR=true/' "${TMPDIR_TEST}/.config/claude-notifier/config.conf"
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state permission
sleep 1.5
assert_contains "sets amber color" "#ff9500" "$MOCK_LOG"

# ── Test 6: Desktop notification ─────────────────
echo "Test 6: Desktop notification — permission state with JSON"
sed -i '.bak' 's/NOTIFY_DESKTOP=false/NOTIFY_DESKTOP=true/' "${TMPDIR_TEST}/.config/claude-notifier/config.conf"
> "$MOCK_LOG"
echo '{"message":"Claude needs your permission to use Bash"}' | "$NOTIFIER" --state permission
sleep 1.5
assert_contains "calls kitten notify" "notify" "$MOCK_LOG"

# ── Test 7: Desktop notification skips working ───
echo "Test 7: Desktop notification — working state does NOT notify"
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
# Wait for any lingering blink subprocess from Test 6 to finish, then reset log
sleep 0.2
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state working
sleep 0.5
assert_not_contains "no notify call for working" "notify.*Claude" "$MOCK_LOG"

# ── Test 8: Version flag ─────────────────────────
echo "Test 8: --version flag"
version_output=$("$NOTIFIER" --version)
if [[ "$version_output" == "claude-notifier 1.0.0" ]]; then
  echo "  PASS: version output correct"
  ((PASS++)) || true
else
  echo "  FAIL: version output was '$version_output'"
  ((FAIL++)) || true
fi

# ── Test 9: Invalid state rejected ──────────────
echo "Test 9: Invalid state rejected"
if echo "" | "$NOTIFIER" --state bogus 2>/dev/null; then
  echo "  FAIL: should have exited non-zero"
  ((FAIL++)) || true
else
  echo "  PASS: invalid state rejected"
  ((PASS++)) || true
fi

# ── Test 10: No --self when KITTY_WINDOW_ID unset ─
echo "Test 10: Fallback to --match pid when no KITTY_WINDOW_ID"
unset KITTY_WINDOW_ID
rm -f "${TMPDIR_TEST}/.config/claude-notifier/.last-working-notify"
> "$MOCK_LOG"
echo "" | "$NOTIFIER" --state working
sleep 0.5
assert_contains "uses --match pid fallback" "--match" "$MOCK_LOG"

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

# ── Test 12: ensure_daemon starts daemon ──────
echo "Test 12: ensure_daemon starts a daemon process"
# Create a simple daemon script that writes a marker file
MOCK_DAEMON="${TMPDIR_TEST}/mock-daemon"
DAEMON_MARKER="${TMPDIR_TEST}/daemon-started"
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

# ── Cleanup ──────────────────────────────────────
rm -rf "$TMPDIR_TEST"

# ── Results ──────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All tests passed!"
