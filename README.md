# Claude Notifier

Visual tab indicators for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in the [Kitty](https://sw.kovidgoyal.net/kitty/) terminal.

Glance at your tab bar and instantly know what Claude is doing — no need to switch tabs.

## What It Does

| State | What You See | When |
|-------|-------------|------|
| **Permission needed** | Tab blinks fast (or turns amber) | Claude needs your approval for a tool |
| **Done** | Tab blinks gently (or turns green) | Claude finished, your turn |
| **Working** | Quick flash (or turns blue) | Claude is actively running tools |
| **Normal** | Your default tab | You're typing or idle |

## Notification Modes

Mix and match — enable any combination:

- **Blink** (default) — flashes the tab using your existing theme. Zero config.
- **Color** — sets a persistent tab color per state (amber/green/blue). Opt-in.
- **Desktop notification** — native OS notification for permission + done. Opt-in.

## Requirements

- [Kitty](https://sw.kovidgoyal.net/kitty/) terminal with `allow_remote_control` enabled
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support
- bash 3.2+
- [jq](https://jqlang.github.io/jq/) (for installation only)

## Install

```bash
git clone https://github.com/<your-username>/claude-notifier.git
cd claude-notifier
./install.sh
```

The installer will:
1. Copy scripts to `~/.config/claude-notifier/`
2. Add Claude Code hooks to `~/.claude/settings.json` (backs up first)
3. Check your Kitty config and offer to enable `allow_remote_control`
4. Run a test blink to confirm it works

## Uninstall

```bash
cd claude-notifier
./uninstall.sh
```

Cleanly removes hooks, restores your settings backup, and deletes installed files.

## Configuration

Edit `~/.config/claude-notifier/config.conf`:

```bash
# Enable/disable modes
NOTIFY_BLINK=true       # Tab blink (default: on)
NOTIFY_COLOR=false      # Persistent tab color (default: off)
NOTIFY_DESKTOP=false    # Desktop notifications (default: off)

# Custom colors (when color mode is on)
COLOR_PERMISSION="#ff9500"   # Amber
COLOR_DONE="#34c759"         # Green
COLOR_WORKING="#007aff"      # Blue

# Timing
BLINK_FAST=0.1          # Fast blink interval (seconds)
BLINK_SLOW=0.3          # Slow blink interval (seconds)
DEBOUNCE_WORKING=3      # Min seconds between working flashes
```

## How It Works

Claude Notifier uses [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — shell commands that run automatically when Claude changes state:

```
Claude Code fires hook event
  → runs claude-notifier --state <permission|done|idle|working>
  → reads your config
  → calls kitten @ (Kitty remote control) to update your tab
```

No polling, no background processes, no network calls. Everything is local.

## Troubleshooting

**Tab doesn't blink:**
- Ensure `allow_remote_control yes` is in your `kitty.conf`
- Restart Kitty after changing config
- Run `claude-notifier --test` to verify

**Blinking is too frequent:**
- Increase `DEBOUNCE_WORKING` in config (default: 3 seconds)

**Works in Kitty but not in tmux/screen:**
- Claude Notifier targets Kitty tabs directly. Terminal multiplexers have their own tab/pane systems and are not supported.

## Privacy

- No data collected or transmitted
- No network calls — all local IPC
- No telemetry
- Hook JSON is read in-memory and discarded
- No API keys or secrets

## License

MIT
