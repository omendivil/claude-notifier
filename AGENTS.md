---
last_updated: 2026-05-07
purpose: Project rules for claude-notifier (Codex twin of CLAUDE.md)
pairs_with_hub: ~/Dev/hub/claude-notifier/
pairs_with_claude_md: ./CLAUDE.md
---

# Claude Notifier

Visual tab indicators for Claude Code in the Kitty terminal. Pure bash, no external runtime dependencies. Hook events from Claude Code update the Kitty tab title, color, and (optionally) fire a desktop notification.

Non-code artifacts (research, planning docs, design notes, audit reports) belong in the hub partner at `~/Dev/hub/claude-notifier/`, not in this repo.

## Build, Install, Test

```bash
# Install (copies bin/ + lib/ to ~/.config/claude-notifier, merges hooks into ~/.claude/settings.json)
./install.sh

# Test suite (mock-based, no Kitty required) — must be 36/36 before pushing
bash tests/test-all.sh

# Lint (CI runs the same command)
shellcheck -x bin/claude-notifier bin/claude-notifier-daemon lib/*.sh install.sh uninstall.sh

# Smoke test against the live install (sends a tab blink)
~/.config/claude-notifier/bin/claude-notifier --test

# Uninstall (removes hooks, files, daemon; preserves config.conf if you say so)
./uninstall.sh
```

CI runs tests + shellcheck on PRs and pushes to main via `.github/workflows/ci.yml`.

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

docs/
├── history/                 # Archival session retrospectives (not active docs)
└── superpowers/             # gitignored — local-only superpowers cache

install.sh                   # Installer — copies files, merges hooks into settings.json
uninstall.sh                 # Uninstaller — removes hooks and installed files
```

### Layer rules

These are strict — do not violate:

- **bin/** calls **lib/** only. Never put business logic in bin/.
- **lib/** files are independent modules. They can read config variables set by `config.sh` but must NOT import from each other (except `kitty.sh`, which is the shared IPC layer).
- **config/** holds only the default config template. User config lives at `~/.config/claude-notifier/config.conf` at runtime.
- **tests/** can source anything for testing purposes.
- **install.sh** and **uninstall.sh** are standalone — they must NOT source lib/ files.

### Data flow

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

## State model (LOCKED)

These are the valid states. Do not add, remove, or rename states without explicit approval.

| State | Tab Title | Trigger |
|-------|-----------|---------|
| `permission` | ⛔ Perm | Notification hook (`permission_prompt`) |
| `done` | ✅ Done | Stop hook |
| `waiting` | ⏳ Wait | Notification hook (`idle_prompt`, `elicitation_dialog`) |
| `idle` | Idle | Daemon: done/waiting exceeds IDLE_TIMEOUT |
| `working` | ⚡ Work | UserPromptSubmit, Notification (`elicitation_response`) |
| `researching` | 🔍 Research | _(no hook trigger — reserved; SubagentStart was removed in v2.1.x to reduce notification cascade)_ |
| `error` | ❌ Error | PostToolUseFailure, StopFailure |
| `normal` | (reset) | Explicit reset |

Cleanup mode (`--cleanup --stdin`) resets tab title/color and removes the session state file. Triggered automatically by the `SessionEnd` hook.

## Code style

### Bash compatibility

- All code must work on bash 3.2+ (macOS ships 3.2; cannot assume 4.x+)
- No `declare -g`, no `local -a`, no associative arrays, no `readarray`
- Use `printf -v` instead of `declare -g` for dynamic variable assignment
- Use `read -ra` for splitting strings into arrays
- Test on both macOS (bash 3.2) and Linux (bash 5.x)
- All scripts use strict mode: `set -euo pipefail`

### Kitty IPC

- All Kitty communication goes through `lib/kitty.sh` — never call `kitten @` directly from other files
- When `KITTY_WINDOW_ID` is set, use `--self` or `--match "id:$KITTY_WINDOW_ID"`
- When not set, fall back to `--match "pid:$PPID"`
- The daemon uses `kitty_set_tab_*_by_id()` variants since it runs detached from the original tab
- All `kitten @` calls must use `2>/dev/null` to suppress errors when Kitty isn't available

## Testing

- Run `bash tests/test-all.sh` before committing
- Tests use mock `kitten` to avoid requiring a Kitty instance
- All tests must pass: currently 36/36
- When adding features, add corresponding test cases
- Shellcheck is enforced in CI; run `shellcheck -x bin/claude-notifier bin/claude-notifier-daemon lib/*.sh install.sh uninstall.sh` before pushing
- The test file itself is exempt from shellcheck in CI (test scaffolding has its own conventions)

## Security

- **Config parsing must NEVER use eval or source.** The safe parser in `config.sh` reads key=value pairs with validation. This is intentional. Do not "simplify" it.
- All `kitten @` calls must use `2>/dev/null` to suppress errors when Kitty isn't available
- No network calls, no telemetry, no data collection — this is a hard privacy constraint
- Hook JSON is read in-memory and discarded — never written to disk beyond state files
- State files contain only: state name, timestamp, kitty window ID, command, tool_use_id, alerted flag

## Daemon

- Single daemon process per user (managed via PID file + mkdir lock)
- Auto-starts on any hook invocation, auto-stops after 5 minutes with no sessions
- Polls every 10 seconds — do not reduce this interval
- Handles: idle transitions (done/waiting → idle), stuck command detection, dead session cleanup (1 hour)

## Constraints (do not do)

- Do not change the state model (add/remove/rename states) without approval
- Do not change the layer boundaries (bin/ → lib/ → config/)
- Do not introduce external runtime dependencies (jq is install-time only)
- Do not use eval, source for config, or any form of code injection in config parsing
- Do not create new top-level directories
- Do not add network calls or telemetry
- Do not break bash 3.2 compatibility
- Do not modify the installer's hook merge strategy (append-based, preserves user's existing hooks)
- Do not re-add hooks that PR #5 deliberately removed (`PreToolUse`, `PostToolUse`, `SubagentStart`, `SubagentStop`) — they caused a notification cascade. Adding more hooks needs a stronger justification than "it's available in the spec."

## Adding new hook events

When Claude Code adds new hook events:

1. Verify the event isn't redundant with an existing wired hook (UserPromptSubmit already covers the working transition; don't re-trigger working from tool events)
2. Add the hook definition in `install.sh` (HOOKS_JSON block) — always include `async: true`
3. Add the hook to the merge logic in `install.sh` (the jq merge block)
4. Map it to an existing state in `bin/claude-notifier` — prefer reusing states over creating new ones
5. Add a test case in `tests/test-all.sh`
6. Update the state model table above with the new trigger

## Pull request guidelines

- Branch naming: `fix/<desc>`, `feature/<desc>`, `refactor/<desc>`, `ci/<desc>`, `docs/<desc>` (per global RULES)
- Run tests + shellcheck before pushing — both are enforced in CI
- One feature/fix per PR; keep diffs reviewable
- Bump the version string in `bin/claude-notifier`, `bin/claude-notifier-daemon`, and the test 8 assertion in `tests/test-all.sh` when the change is functional (not pure docs)
- After merge: re-run `./uninstall.sh && ./install.sh` to apply hook changes (the installer's "skip if already present" guard prevents a plain re-run from picking up new hook entries)
- Auto-merge with `gh pr merge <num> --auto --squash` when branch protection allows; otherwise merge manually after CI passes

## Stack

- **Language:** Bash 3.2+ (strict mode: `set -euo pipefail`)
- **Runtime deps:** Kitty terminal with `allow_remote_control`, bash
- **Install-time deps:** jq (for JSON merge into settings.json)
- **IPC:** `kitten @` (Kitty remote control protocol)
- **CI:** GitHub Actions — runs tests + shellcheck on PRs and pushes to main
- **Linting:** shellcheck (enforced in CI)

## Cross-references

- Hub partner: `~/Dev/hub/claude-notifier/` — research, planning, design notes
- Global rules: `~/Dev/hub/global-rules/RULES.md`
- Claude twin: `CLAUDE.md` (in this repo) — canonical; this file mirrors it for Codex CLI
- Session continuity: `LEAVE-OFF.md` (in this repo) — current state, written at session end
