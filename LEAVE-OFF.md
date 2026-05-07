---
captured: 2026-05-07 11:00 MST
domain: claude-notifier
purpose: Session handoff after the v2.2.0 ship and project-conventions update
---

# claude-notifier — LEAVE-OFF

## State

- **Branch:** `docs/agents-md-spec-and-leave-off` (uncommitted, not yet pushed)
- **Main HEAD:** `53a23d0` (PR #6 merged — v2.2.0 with per-session debounce + elicitation matchers)
- **Uncommitted on this branch:**
  - Modified: `.gitignore` (removed `agent-log.md` line — file moved)
  - Modified: `CLAUDE.md` (full agents.md spec restructure)
  - New: `AGENTS.md` (Codex twin)
  - New: `docs/history/agent-log-2026-03-13.md` (moved from root, no longer gitignored)
- **Hub partner created (uncommitted in hub repo):** `~/Dev/hub/claude-notifier/CLAUDE.md`

The user has not yet run `./uninstall.sh && ./install.sh` to activate the v2.2.0 elicitation hook entries in `~/.claude/settings.json`. The dispatcher binary changes (per-session debounce) are inert until the install copies them. **This is the only outstanding action before claude-notifier is fully active in v2.2.0 form.**

## Where we are

Two threads moved this session.

**Thread 1 (shipped, PR #6):** Audited claude-notifier against the current Claude Code hook spec and Codex CLI hook surface. Headline finding: zero breaking drift in Claude Code — every hook event, matcher, and payload field claude-notifier depends on is current as of 2026-05-07. The user's "running a lot causing issues" concern was a combination of (a) PR #5's prior-shipped fix for the notification cascade and (b) one remaining bug: the global debounce file collided across concurrent Claude sessions. v2.2.0 ships per-session debounce plus MCP elicitation matchers (`elicitation_dialog` → waiting, `elicitation_response` → working) that didn't exist when v2.1.0 shipped. Tests at 36/36, shellcheck clean. Deliberately dropped re-introduction of `SubagentStart`/`SubagentStop` and addition of `PreCompact`/`PostCompact` after discovering PR #5's intent; documented this in the constraints section so future audits don't re-add them.

**Thread 2 (in progress, this branch):** Updated the project to follow current global conventions. Restructured `CLAUDE.md` to agents.md spec section ordering (Project overview → Build/Install/Test → Architecture → State Model → Code Style → Testing → Security → Daemon → Constraints → Adding hooks → PR guidelines → Stack → Cross-references). Created `AGENTS.md` as a near-duplicate Codex twin (same pattern as `~/Dev/hub/`'s CLAUDE.md/AGENTS.md pair). Created hub partner at `~/Dev/hub/claude-notifier/CLAUDE.md` for future research and planning artifacts. Moved `agent-log.md` (a one-off design retrospective from project inception) into `docs/history/agent-log-2026-03-13.md` per the leave-off spec's "dated session files don't belong at root" rule. Removed it from `.gitignore` since it's now a tracked archival doc.

## What landed this session

**Code (PR #6, merged into main):**
- v2.2.0 dispatcher with per-session debounce file (`.last-working-notify-${SESSION_ID}` instead of a single global file)
- `Notification` matchers for MCP elicitation flow (`elicitation_dialog` → waiting, `elicitation_response` → working)
- CLAUDE.md state model table updated to reflect post-PR-#5 reality (working driven only by `UserPromptSubmit` plus the new elicitation matcher; `researching` has no hook trigger; `SessionEnd` cleanup hook documented)
- Uninstall debounce cleanup uses a glob to catch all per-session files
- Test 19 added: per-session debounce isolation (36/36 passes, was 33/33)

**Conventions (this branch, uncommitted):**
- `CLAUDE.md` restructured to agents.md spec ordering with explicit Build/Install/Test, PR Guidelines, and Cross-references sections
- `AGENTS.md` created as Codex twin (frontmatter notes "Codex twin of CLAUDE.md")
- `~/Dev/hub/claude-notifier/CLAUDE.md` created — hub partner routing stub
- `agent-log.md` moved to `docs/history/agent-log-2026-03-13.md` and added to git (was previously gitignored)
- `.gitignore` updated to drop the agent-log entry

**Codex (out-of-band):**
- Removed dead `[features].codex_hooks = true` flag from `~/.codex/config.toml` (stable since 2026, was a no-op)
- Codex CLI bump 0.128 → 0.129 deferred — brew formula not yet updated as of 2026-05-07

**Memory:**
- Added `project_audit_2026_05_07.md` to claude-notifier memory: Claude Code hook surface stable, current state model post-v2.2.0, Codex CLI parity research, deferred items
- Cleaned `MEMORY.md` index (had a duplicated Project section)

## Decisions locked

- **No re-adding `PreToolUse`, `PostToolUse`, `SubagentStart`, `SubagentStop`.** PR #5 removed them deliberately. Source: `CLAUDE.md` Constraints section + `project_audit_2026_05_07.md` memory entry.
- **No `PreCompact` / `PostCompact` hooks.** Considered, dropped after rebasing onto PR #5. Source: PR #6 description.
- **`researching` state is dead code.** Kept in dispatcher for future use but flagged in CLAUDE.md state model table.
- **CLAUDE.md and AGENTS.md are near-duplicate files (not symlinks).** Mirrors the pattern in `~/Dev/hub/`. Frontmatter differs by one line.
- **Hub partner created at `~/Dev/hub/claude-notifier/`.** Future research and planning go there, not in the code repo. Source: `~/Dev/hub/claude-notifier/CLAUDE.md`.

## Open / pending (carry forward)

- **`pending-user-action:`** Run `./uninstall.sh && ./install.sh` from `~/Dev/claude-notifier/` to activate v2.2.0 hook entries in `~/.claude/settings.json`. Dispatcher binary upgrade ships transparently; only the new elicitation matchers need re-merge.
- **`pending-commit:`** Branch `docs/agents-md-spec-and-leave-off` has uncommitted changes (CLAUDE.md, AGENTS.md, .gitignore, docs/history/agent-log-2026-03-13.md). Hub partner at `~/Dev/hub/claude-notifier/CLAUDE.md` also uncommitted. Plan: commit + PR after this leave-off is written.
- **`external-waiting:`** Codex CLI bump 0.128 → 0.129. Run `brew upgrade codex` again in a few days; brew formula will catch up.
- **`deferred:`** Codex-notifier mode (visual tab indicators driven by Codex CLI hooks). Codex has full hook parity (same event names: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, plus PermissionRequest). ~80% reuse of existing dispatcher. User explicitly deferred this in 2026-05-07 session ("skip notifications track right now").
- **`deferred:`** Yes/No conversational question state (Bug 1 from `project_session_notes_2026_03_18`). Possibly partially addressed by the new elicitation matchers, but conversational questions vs MCP elicitations are different surfaces. Verify after install.
- **`deferred:`** Last-tab targeting bug (Bug 2 from `project_session_notes_2026_03_18`).
- **`deferred:`** Auto-switch mode + dynamic tab title sizing (feature requests from `project_session_notes_2026_03_18`).

## Next session: start here

1. Run `date '+%Y-%m-%d %H:%M %Z'` to anchor time.
2. `cd ~/Dev/claude-notifier && git status` — confirm whether the docs branch was committed/PR'd or still pending.
3. Confirm with the user whether `./uninstall.sh && ./install.sh` was run since last session. If yes, update this leave-off's "pending-user-action" → "done." If no, prompt them to run it before any new feature work.
4. Verify the install took: `grep -c claude-notifier ~/.claude/settings.json` should show many matches; `grep elicitation_dialog ~/.claude/settings.json` should show the new matcher.
5. If user wants to keep working on claude-notifier itself, the next priorities (in order) are: yes/no question state research → last-tab targeting bug → auto-switch mode (the three bugs from `project_session_notes_2026_03_18` that haven't been touched since March).
6. If user wants to start codex-notifier, see `project_audit_2026_05_07.md` memory for the design sketch (deferred per 2026-05-07 decision).

## Files / paths that matter

**Code repo (`~/Dev/claude-notifier/`):**
- `CLAUDE.md`, `AGENTS.md` — project rules (canonical: CLAUDE.md; AGENTS.md mirrors)
- `LEAVE-OFF.md` — this file
- `bin/claude-notifier`, `bin/claude-notifier-daemon` — v2.2.0
- `install.sh`, `uninstall.sh` — installer scripts
- `tests/test-all.sh` — 36 test suite
- `.github/workflows/ci.yml` — CI (tests + shellcheck)
- `docs/history/agent-log-2026-03-13.md` — archived design retrospective
- `docs/superpowers/` — gitignored local cache

**Hub partner (`~/Dev/hub/claude-notifier/`):**
- `CLAUDE.md` — routing stub for research/planning artifacts

**Live install (`~/.config/claude-notifier/`):**
- `bin/`, `lib/`, `config.conf` — runtime files (overwritten by install.sh)
- `sessions/*.state` — per-session state files (transient)
- `.daemon.pid`, `.daemon.lock` — daemon lifecycle
- `.last-working-notify-*` — per-session debounce files (new in v2.2.0)

**Settings (`~/.claude/settings.json`):**
- Hook entries for UserPromptSubmit, Notification (4 matchers post-v2.2.0), Stop, StopFailure, PostToolUseFailure, SessionEnd

**Memory (`~/.claude/projects/-Users-omendivil-Dev-claude-notifier/memory/`):**
- `MEMORY.md` — index
- `project_audit_2026_05_07.md` — full audit findings + deferred work
- `project_session_notes_2026_03_18.md` — older session notes (3 bugs + 2 feature requests, mostly untouched)

## Commits this session

- `4d4c272..53a23d0` on main — PR #6 squashed merge (v2.2.0)
- `docs/agents-md-spec-and-leave-off` branch — pending commit (this leave-off + the convention updates above)
