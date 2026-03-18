# Improved State Model & Daemon — Design Spec

## Problem

The current claude-notifier has state accuracy issues:
1. Shows wrong state after permission approval (no "approved" event exists)
2. `UserPromptSubmit` sets `normal` instead of `working`
3. `SubagentStart` maps to `researching` which isn't a valid state
4. No visibility into tool failures
5. No time-based transitions (done → idle after inactivity)
6. No stuck detection for hanging commands (npm install prompts, dead servers)
7. Up to 20 simultaneous sessions need monitoring without 20 watchdog processes

## Solution

Three changes: expanded state model (8 states), a single background daemon for time-based transitions, and stuck detection for known-hangable commands.

## Dependencies

- **jq** is now required at runtime (not just install time). Extracting nested JSON fields like `tool_input.command` from hook stdin is impractical without it. The existing grep fallback is only reliable for simple top-level fields.

## State Model

### States

| State | Title | Color | Blink | Desktop Notify | Trigger |
|---|---|---|---|---|---|
| `working` | `⚡ Work` | `#b026ff` (purple) | 1 short flash | No | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStop` |
| `permission` | `⛔ Perm` | `#ff003c` (red) | 3 fast blinks | Yes (tool message) | `Notification(permission_prompt)` |
| `researching` | `🔍 Research` | `#007aff` (blue) | 1 short flash | No | `SubagentStart` |
| `error` | `❌ Error` | `#ff6b00` (orange) | 2 fast blinks | Yes (error message) | `PostToolUseFailure` |
| `done` | `✅ Done` | `#00ffd5` (cyan) | 2 slow pulses | Yes ("Claude is done") | `Stop` |
| `waiting` | `⏳ Wait` | `#00ffd5` (cyan) | No blink | No | `Notification(idle_prompt)` (~60s after done) |
| `idle` | `💤 Idle` | None (reset) | 1 slow pulse (reminder) | No | Daemon: `IDLE_TIMEOUT` elapsed since last state change |
| `normal` | (empty) | None (reset) | No blink | No | Manual reset via `--state normal` |

### Transition Flow

Any state can transition to any other state. The complete valid transitions:

```
UserPromptSubmit → ⚡ working
  ├→ PreToolUse → ⚡ working (maintained)
  ├→ PostToolUse → ⚡ working (clears permission/error)
  ├→ PostToolUseFailure → ❌ error
  │    ├→ PreToolUse → ⚡ working (next tool clears error)
  │    ├→ Stop → ✅ done (session ends in error state)
  │    └→ Notification(permission_prompt) → ⛔ permission
  ├→ Notification(permission_prompt) → ⛔ permission
  │    └→ PostToolUse → ⚡ working (approved tool finishes)
  ├→ SubagentStart → 🔍 researching
  │    └→ SubagentStop → ⚡ working
  ├→ Stop → ✅ done
  │    └→ Notification(idle_prompt) → ⏳ waiting (~60s later)
  │         └→ Daemon → 💤 idle (IDLE_TIMEOUT after last state change)
  └→ manual → normal (reset)
```

### IDLE_TIMEOUT Semantics

The `IDLE_TIMEOUT` (default 300s) counts from the **timestamp of the last state file write**. This means:
- `Stop` fires → state=done, timestamp=T
- `Notification(idle_prompt)` fires ~60s later → state=waiting, timestamp=T+60 (resets clock)
- Daemon checks: elapsed since T+60 > 300s? → transition to idle at ~T+360

The `waiting` state resets the timer. Total time from `done` to `idle` is approximately 360 seconds (60s Claude idle_prompt + 300s IDLE_TIMEOUT).

At the idle transition, the daemon fires one blink reminder to catch attention, then sets the tab to idle (color reset, title "💤 Idle").

### Stuck Detection (Title Overlay)

When a watched command runs longer than `STUCK_TIMEOUT`:
- Title changes to show elapsed time: `⏰ npm 3m`
- Desktop notification fires (once per stuck event)
- Color stays purple (working) — stuck is a title overlay, not a state
- Title updates every daemon poll with new elapsed: `⏰ npm 4m`, `⏰ npm 5m`
- Clears when `PostToolUse` fires (tool finished)

Watched commands (configurable via `STUCK_COMMANDS`):
- `install` (npm/yarn/bun/pip/cargo install)
- `init`, `create-` (interactive scaffolding)
- `run dev`, `run start`, `serve` (dev servers)

**Matching algorithm:** The daemon extracts the first keyword from the stored command (e.g., `npm install react` → checks if `install` matches any pattern in `STUCK_COMMANDS`). The match is performed against individual space-separated tokens in the command, not as a substring of the full string. This prevents false positives like `echo "do not install"`.

For multi-word patterns like `run dev`, the daemon checks consecutive tokens. Example: `npm run dev --port 3000` → tokens `npm`, `run`, `dev` → matches `run dev`.

## Architecture

### Layer 1: Hook Handler (bin/claude-notifier)

Enhanced to:
1. Read JSON from stdin via `jq` on every invocation (extract `session_id`, `tool_name`, `tool_input.command`, `tool_use_id`)
2. Set tab title/color/blink immediately (same as today)
3. Write session state file to `~/.config/claude-notifier/sessions/<session_id>.state`
4. Call `ensure_daemon()` to start daemon if not running

**Debounce vs state file writes:** The existing debounce (3s for `working` state) applies ONLY to visual notifications (blink/color/title). State file writes always happen regardless of debounce. This ensures the daemon always has accurate state data even when visual updates are throttled.

**--stdin flag:** When present, the handler reads JSON from stdin and extracts fields. When absent (manual invocation, e.g., `--state normal`), no JSON is expected.

**--cleanup flag:** Used by the `SessionEnd` hook. Reads `session_id` from stdin JSON, removes the corresponding session state file, and resets the tab to default appearance (title empty, color NONE).

State file format:
```
state=working
timestamp=1710700000
kitty_window_id=42
command=npm install
tool_use_id=toolu_abc123
alerted=false
```

### Layer 2: Daemon (bin/claude-notifier-daemon)

Single background process monitoring all sessions.

**Startup:** `ensure_daemon()` called by every hook invocation.
```
1. Try mkdir ~/.config/claude-notifier/.daemon.lock (atomic)
   - If lock dir exists AND is older than 30s: force-remove (stale lock guard)
2. If acquired: check PID file, start daemon if not running, release lock (rmdir)
3. If not acquired: another hook is checking, skip
```

**Main loop:** Poll `sessions/` directory every 10 seconds.
```
For each session state file:
  - If state=done|waiting AND elapsed > IDLE_TIMEOUT:
    → Blink reminder (using kitty_window_id from state file)
    → Set title "💤 Idle", color NONE
    → Update state file to idle
  - If command is set AND matches STUCK_COMMANDS AND elapsed > STUCK_TIMEOUT:
    → If not alerted: send desktop notification, set alerted=true in state file
    → Update title to "⏰ <cmd> <elapsed>m"
  - If state file older than 1 hour:
    → Remove (dead session cleanup)
```

**Kitty tab targeting from daemon:** The daemon is NOT a child of any Kitty session. It must use `kitten @ set-tab-title --match "id:<window_id>"` with the `kitty_window_id` read from each session's state file. This requires a new helper function in `kitty.sh`:

```bash
kitty_set_tab_color_by_id() {
  local window_id="$1"; shift
  kitten @ set-tab-color --match "id:${window_id}" "$@" 2>/dev/null
}

kitty_set_tab_title_by_id() {
  local window_id="$1"; shift
  kitten @ set-tab-title --match "id:${window_id}" "$@" 2>/dev/null
}
```

**Auto-stop:** 30 consecutive polls (5 min) with no session files → daemon exits, removes PID file.

**Crash recovery:** Stale PID file detected by `kill -0` failure in `ensure_daemon()`. Removed and daemon restarted.

### Layer 3: Config (config/default.conf)

New keys:
```bash
IDLE_TIMEOUT=300              # seconds before done/waiting → idle
STUCK_TIMEOUT=180             # seconds before watched command alerts
STUCK_COMMANDS="install|init|create-|run dev|run start|serve"
COLOR_RESEARCHING="#007aff"   # blue
COLOR_ERROR="#ff6b00"         # orange
```

The config parser (`lib/config.sh`) must be updated to:
- Add these keys to the allowlist
- Validate `IDLE_TIMEOUT` and `STUCK_TIMEOUT` as positive numbers
- Validate `STUCK_COMMANDS` as a pipe-delimited string (allow alphanumeric, hyphens, spaces, pipes)
- Validate new color values as hex `#rrggbb`

**Upgrade path for existing users:** The `install.sh` will NOT overwrite existing `config.conf` files. New config keys that are missing from the user's config will use the hardcoded defaults in `lib/config.sh`. This is the same pattern used today — `config.sh` defines defaults, the config file overrides them.

## Hook Configuration

Updated `settings.json` hooks:

| Hook Event | Matcher | Command |
|---|---|---|
| `UserPromptSubmit` | — | `claude-notifier --state working --stdin` |
| `PreToolUse` | `.*` | `claude-notifier --state working --stdin` |
| `PostToolUse` | `.*` | `claude-notifier --state working --stdin` |
| `PostToolUseFailure` | `.*` | `claude-notifier --state error --stdin` |
| `Notification` | `permission_prompt` | `claude-notifier --state permission --stdin` |
| `Notification` | `idle_prompt` | `claude-notifier --state waiting --stdin` |
| `Stop` | — | `claude-notifier --state done --stdin` |
| `SubagentStart` | `.*` | `claude-notifier --state researching --stdin` |
| `SubagentStop` | `.*` | `claude-notifier --state working --stdin` |
| `SessionEnd` | — | `claude-notifier --cleanup --stdin` |

All hooks pass `--stdin` to enable JSON extraction of `session_id` and tool metadata.

`PostToolUseFailure` is a confirmed Claude Code hook event (separate from `PostToolUse`) that fires after a tool call fails. It provides `error` and `is_interrupt` fields in the JSON payload.

## File Structure

```
bin/
  claude-notifier            # enhanced main dispatcher
  claude-notifier-daemon     # new background daemon
lib/
  blink.sh                   # add error, researching blink patterns
  color.sh                   # add researching, error, waiting, idle states
  config.sh                  # add new config keys + validation
  kitty.sh                   # add kitty_set_tab_*_by_id() helpers for daemon
  notify.sh                  # add error notification
  state.sh                   # new: read/write state files, ensure_daemon()
  stuck.sh                   # new: stuck command matching + elapsed time formatting
config/
  default.conf               # add new config keys
tests/
  test-all.sh                # update for new states + add daemon tests
install.sh                   # register new hooks, install daemon, create sessions/
uninstall.sh                 # kill daemon, remove sessions/, PID file, state files
```

## Testing Strategy

- **Unit tests (existing pattern):** Mock `kitten` command, test each state triggers correct tab title/color/blink. Extend for new states (researching, error, waiting, idle).
- **State file tests:** Verify state files are written correctly, read back accurately, cleaned up on session end.
- **Daemon tests:** Start daemon, write test state files with old timestamps, verify daemon transitions them. Use short timeouts (1-2s) in test mode to avoid slow tests.
- **Stuck detection tests:** Write a state file with a watched command and an old timestamp, verify daemon updates the title and sends notification.
- **Ensure_daemon tests:** Verify PID file management, stale PID cleanup, lock staleness guard.

## Version

This release will be versioned as `2.0.0` — the state model expansion, daemon addition, and jq runtime requirement are breaking changes from 1.0.0.

## Known Limitations

These cannot be fixed with the hook system:

1. **No "thinking" event** — Between tool calls when Claude generates text, no hooks fire. State stays at whatever it was last set to.
2. **No "permission approved" event** — Between user approval and `PostToolUse`, state is indeterminate. `PostToolUse` clears it once the tool finishes.
3. **No heartbeat during tool execution** — Between `PreToolUse` and `PostToolUse`, we're blind. The daemon's stuck detection is the workaround.
4. **One session per Kitty tab assumed** — If two Claude sessions share a tab (split panes), their state files will target the same window ID and overwrite each other's visual state. This is unsupported.

## Future Work (Not In Scope)

- Homebrew tap distribution
- curl | bash remote installer
- Nix flake
- launchd plist for boot-time daemon start
- Process-level stuck detection (monitoring subprocess CPU/stdin state)
