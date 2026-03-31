# Claude Notifier

Visual tab indicators for Claude Code in the Kitty terminal. Pure bash, no external runtime dependencies.

## Architecture

```
bin/
├── claude-notifier          # Main dispatcher — parses args, reads stdin JSON, dispatches to lib/
└── claude-notifier-daemon   # Background process — polls session state files for time-based transitions

lib/
├── kitty.sh                 # Kitty IPC layer — all kitten @ commands go through here
├── blink.sh                 # Blink mode — tab flash via set-tab-color toggle
├── color.sh                 # Color mode — persistent tab color per state
├── notify.sh                # Desktop notification mode — kitten notify
├── config.sh                # Config loader — safe key=value parsing (NO eval/source)
├── state.sh                 # Session state file management + daemon lifecycle
└── stuck.sh                 # Stuck command detection and elapsed time formatting

config/
└── default.conf             # Default config shipped with install

tests/
└── test-all.sh              # Full test suite (mock-based, no Kitty required)

install.sh                   # Installer — copies files, merges hooks into settings.json
uninstall.sh                 # Uninstaller — removes hooks and installed files
```

### Layer Rules

These are strict — do not violate:

- **bin/** calls **lib/** only. Never put business logic in bin/.
- **lib/** files are independent modules. They can read config variables set by `config.sh` but must NOT import from each other (except `kitty.sh` which is the shared IPC layer).
- **config/** holds only the default config template. User config lives at `~/.config/claude-notifier/config.conf` at runtime.
- **tests/** can source anything for testing purposes.
- **install.sh** and **uninstall.sh** are standalone — they must NOT source lib/ files.

### Data Flow

```
Claude Code fires hook event
  → bin/claude-notifier --state <state> --stdin
    → reads stdin JSON (session_id, tool_name, etc.)
    → loads config (lib/config.sh)
    → writes state file (lib/state.sh)
    → ensures daemon is running (lib/state.sh)
    → dispatches to enabled modes:
        → lib/blink.sh   (tab flash)
        → lib/color.sh   (persistent color)
        → lib/notify.sh  (desktop notification)
```

## State Model (LOCKED)

These are the valid states. Do not add, remove, or rename states without explicit approval.

| State | Tab Title | Trigger |
|-------|-----------|---------|
| `permission` | ⛔ Perm | Notification hook (permission_prompt) |
| `done` | ✅ Done | Stop hook |
| `waiting` | ⏳ Wait | Notification hook (idle_prompt) |
| `idle` | Idle | Daemon: done/waiting exceeds IDLE_TIMEOUT |
| `working` | ⚡ Work | UserPromptSubmit, PreToolUse, PostToolUse, SubagentStop |
| `researching` | 🔍 Research | SubagentStart |
| `error` | ❌ Error | PostToolUseFailure, StopFailure |
| `normal` | (reset) | Explicit reset |

Cleanup mode (`--cleanup --stdin`) resets tab title/color and removes the session state file.

## Rules

### Bash Compatibility
- **All code must work on bash 3.2+** (macOS ships 3.2, cannot assume 4.x+)
- No `declare -g`, no `local -a`, no associative arrays, no `readarray`
- Use `printf -v` instead of `declare -g` for dynamic variable assignment
- Use `read -ra` for splitting strings into arrays
- Test on both macOS (bash 3.2) and Linux (bash 5.x)

### Security
- **Config parsing must NEVER use eval or source** — the safe parser in `config.sh` reads key=value pairs with validation. This is intentional. Do not "simplify" it.
- All `kitten @` calls must use `2>/dev/null` to suppress errors when Kitty isn't available
- No network calls, no telemetry, no data collection — this is a hard privacy constraint
- Hook JSON is read in-memory and discarded — never written to disk beyond state files
- State files contain only: state name, timestamp, kitty window ID, command, tool_use_id, alerted flag

### Kitty IPC
- All Kitty communication goes through `lib/kitty.sh` — never call `kitten @` directly from other files
- When `KITTY_WINDOW_ID` is set, use `--self` or `--match "id:$KITTY_WINDOW_ID"`
- When not set, fall back to `--match "pid:$PPID"`
- The daemon uses `kitty_set_tab_*_by_id()` variants since it runs detached from the original tab

### Daemon
- Single daemon process per user (managed via PID file + mkdir lock)
- Auto-starts on any hook invocation, auto-stops after 5 minutes with no sessions
- Polls every 10 seconds — do not reduce this interval
- Handles: idle transitions (done/waiting → idle), stuck command detection, dead session cleanup (1 hour)

### What You Must NOT Do
- Do not change the state model (add/remove/rename states) without approval
- Do not change the layer boundaries (bin/ → lib/ → config/)
- Do not introduce external runtime dependencies (jq is install-time only)
- Do not use eval, source for config, or any form of code injection in config parsing
- Do not create new top-level directories
- Do not add network calls or telemetry
- Do not break bash 3.2 compatibility
- Do not modify the installer's hook merge strategy (append-based, preserves user's existing hooks)

### Adding New Hook Events
When Claude Code adds new hook events:
1. Add the hook definition in `install.sh` (HOOKS_JSON block) — always include `async: true`
2. Add the hook to the merge logic in `install.sh` (the jq merge block)
3. Map it to an existing state in `bin/claude-notifier` — prefer reusing states over creating new ones
4. Update tests if the version or behavior changes

### Testing
- Run `bash tests/test-all.sh` before committing
- Tests use mock `kitten` to avoid requiring a Kitty instance
- All tests must pass: currently 33/33
- When adding features, add corresponding test cases

## Stack
- **Language:** Bash 3.2+ (strict mode: `set -euo pipefail`)
- **Runtime deps:** Kitty terminal with `allow_remote_control`, bash
- **Install-time deps:** jq (for JSON merge into settings.json)
- **IPC:** `kitten @` (Kitty remote control protocol)
- **CI:** GitHub Actions — runs tests + shellcheck on PRs and pushes to main
- **Linting:** shellcheck (enforced in CI)
