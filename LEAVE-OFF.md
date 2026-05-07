---
captured: 2026-05-07 13:05 MST
domain: claude-notifier
purpose: Session handoff after v2.2.0 ship, project-conventions update, and live install activation
---

# claude-notifier — LEAVE-OFF

## State

- **Branch:** `main` (clean working tree)
- **Main HEAD:** `d0c3ec7` (PR #7 merged — agents.md spec + AGENTS.md + LEAVE-OFF.md + hub partner)
- **Previous merge:** `53a23d0` (PR #6 — v2.2.0 with per-session debounce + elicitation matchers)
- **Live install:** v2.2.0 active. Verified 2026-05-07 13:00 MST:
  - `~/.config/claude-notifier/bin/claude-notifier --version` → `claude-notifier 2.2.0`
  - Per-session debounce path (`SESSION_ID:-shared`) present in live dispatcher
  - All 4 Notification matchers in `~/.claude/settings.json`: `permission_prompt`, `idle_prompt`, `elicitation_dialog`, `elicitation_response`
  - Test blink ran successfully during install
- **Hub partner:** `~/Dev/hub/claude-notifier/CLAUDE.md` (committed to hub main, hub has no remote)

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

- **`external-waiting:`** Codex CLI bump 0.128 → 0.129. Run `brew upgrade codex` again in a few days; brew formula will catch up.
- **`deferred:`** Codex-notifier mode (visual tab indicators driven by Codex CLI hooks). Codex has full hook parity (same event names: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, plus PermissionRequest). ~80% reuse of existing dispatcher. User explicitly deferred this in 2026-05-07 session ("skip notifications track right now").
- **`deferred:`** Yes/No conversational question state (Bug 1 from `project_session_notes_2026_03_18`). Possibly partially addressed by the new elicitation matchers, but conversational questions vs MCP elicitations are different surfaces. Verify after install.
- **`deferred:`** Last-tab targeting bug (Bug 2 from `project_session_notes_2026_03_18`).
- **`deferred:`** Auto-switch mode + dynamic tab title sizing (feature requests from `project_session_notes_2026_03_18`).

## Next session: start here

1. Run `date '+%Y-%m-%d %H:%M %Z'` to anchor time.
2. `cd ~/Dev/claude-notifier && git status` — should be clean on `main`.
3. Quick sanity check that v2.2.0 is still active: `~/.config/claude-notifier/bin/claude-notifier --version` → expect `claude-notifier 2.2.0`. If it doesn't, an upgrade or rogue install elsewhere may have overwritten it.
4. If user wants to keep working on claude-notifier itself, the next priorities (in order) are: yes/no question state research → last-tab targeting bug → auto-switch mode (the three bugs from `project_session_notes_2026_03_18` that haven't been touched since March).
5. If user wants to start codex-notifier, see `project_audit_2026_05_07.md` memory for the design sketch (deferred per 2026-05-07 decision).
6. If user has been using v2.2.0 for a while: ask whether the "running a lot causing issues" feeling has improved. If yes, the per-session debounce was the culprit. If no, dig into the daemon polling cost or hook fan-out further.

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
- `53a23d0..d0c3ec7` on main — PR #7 squashed merge (agents.md spec + AGENTS.md + LEAVE-OFF.md + hub partner)
- `~/Dev/hub` `506c7bf` — created `claude-notifier/` partner directory (direct to hub main, no remote)
- Live `~/.config/claude-notifier/` upgraded to v2.2.0 via `./uninstall.sh && ./install.sh` (2026-05-07 13:00 MST)
