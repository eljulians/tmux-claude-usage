# tmux-claude-usage

[![tests](https://github.com/OWNER/tmux-claude-usage/actions/workflows/test.yml/badge.svg)](https://github.com/OWNER/tmux-claude-usage/actions/workflows/test.yml)
[![license](https://img.shields.io/github/license/OWNER/tmux-claude-usage?color=blue)](LICENSE)
[![tmux](https://img.shields.io/badge/tmux-3.0+-1bb91f.svg)](https://github.com/tmux/tmux)
[![bash](https://img.shields.io/badge/bash-4.0+-4EAA25.svg?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey.svg)](#requirements)

Your Claude Code usage limits in the tmux status bar.

```
󰚩 Claude 5h:26% 7d:3%          # compact (default)
󰚩 Claude ▰▰▰▱▱▱▱▱▱▱ ~26%      # gauge
󰚩 ~26%                          # minimal
```

No switching to the web console. Color-coded at a glance. Zero config to start.

---

## Two modes: local (default) vs exact

| | Local | Exact (web API) |
|---|---|---|
| **Setup** | None - works immediately | Paste a browser session key once |
| **Data source** | `~/.claude/projects/` JSONL files | Claude.ai web API |
| **Accuracy** | Approximate (`~26%`) | Exact (`26%`) |
| **Tiers shown** | 5h only | 5h + 7d + per-model |
| **Reset times** | Not available | Shown when near limit |

**The `~` prefix means approximate.** Local mode estimates cost from raw token counts using community-sourced price tables. Good enough for "am I close to the limit?" - not guaranteed to match what Anthropic actually counts.

**No `~` means exact.** When a session key is configured the plugin hits the same endpoint the Claude.ai dashboard uses. Numbers match exactly.

The session key is entirely optional. If you never set it you get local mode forever, which is fine for most people.

---

## Features

- **Zero-setup default** - reads local Claude Code data, no credentials needed
- **Optional exact mode** - add a browser session key for precise numbers
- **Color temperature** - green → yellow → orange → red as usage climbs
- **Three display presets** - `compact`, `gauge` (with bar), `minimal`
- **TPM compatible** - install with `set -g @plugin ...`
- **tmux-powerline compatible** - drop-in segment
- **Bare install** - works without any plugin manager

---

## Requirements

- tmux ≥ 3.0
- bash ≥ 4.0
- `jq` (recommended) **or** `python3` (fallback) - for JSONL parsing
- Claude Code installed and used at least once (data lives in `~/.claude/projects/`)

---

## Install

### With TPM (recommended)

```tmux
# ~/.tmux.conf
set -g @plugin 'your-username/tmux-claude-usage'   # TODO: final repo path

# Add placeholder wherever you want it in your status bar
set -g status-right '#{claude_usage} | %H:%M'

# Reload and install
# prefix + I
```

### Bare (no TPM)

```tmux
# ~/.tmux.conf
run-shell "~/.tmux/plugins/tmux-claude-usage/claude-usage.tmux"
set -g status-right '#{claude_usage} | %H:%M'
```

Or call the script directly (skips placeholder replacement):

```tmux
set -g status-right '#(~/.tmux/plugins/tmux-claude-usage/scripts/claude_usage.sh) | %H:%M'
```

### With tmux-powerline

```bash
# Copy the segment
cp segments/claude_usage.sh ~/.config/tmux-powerline/segments/

# Add to your powerline theme's right segments:
# "claude_usage 235 82"
```

---

## Configuration

All options are optional - defaults work out of the box.

```tmux
# ~/.tmux.conf

# Display preset:
#   compact  (default) - 󰚩 Claude 5h:26% 7d:3%       multi-tier, no bar
#   gauge              - 󰚩 Claude ▰▰▰▱▱▱▱▱▱▱ ~26%    visual bar, primary tier
#   minimal            - 󰚩 ~26%                        icon + pct only
set -g @claude_usage_format "compact"

# Gauge bar width (blocks), only used by the gauge preset
set -g @claude_usage_gauge_width "10"

# Icon and label (set label to "" to hide it)
set -g @claude_usage_icon  "󰚩"
set -g @claude_usage_label "Claude"

# Color thresholds (%)
set -g @claude_usage_threshold_warn "60"   # → yellow
set -g @claude_usage_threshold_high "80"   # → orange
set -g @claude_usage_threshold_crit "95"   # → red

# Colors (tmux colour names)
set -g @claude_usage_color_normal "colour82"
set -g @claude_usage_color_warn   "colour220"
set -g @claude_usage_color_high   "colour208"
set -g @claude_usage_color_crit   "colour196"

# Cache duration in seconds (default 60)
set -g @claude_usage_cache_seconds "60"

# Plan override - "auto" reads from ~/.claude/.credentials.json
# Options: auto | pro | max5 | max20
set -g @claude_usage_plan "auto"
```

---

## Exact mode setup

1. Go to [claude.ai](https://claude.ai) in your browser
2. DevTools → Application → Cookies → `claude.ai`
3. Copy the `sessionKey` value (starts with `sk-ant-sid01-...`)
4. Add to `~/.tmux.conf`:
   ```tmux
   set -g @claude_usage_session_key "sk-ant-sid01-..."
   ```

The session key expires after weeks to months. When it does, the plugin falls back to local mode automatically and the `~` reappears.

---

## Development

```bash
# Run all tests
./tests/bats/bin/bats tests/

# Run specific suite
./tests/bats/bin/bats tests/test_fetch.bats
./tests/bats/bin/bats tests/test_format.bats
./tests/bats/bin/bats tests/test_cache.bats

# Smoke test the pipeline
bash scripts/claude_usage.sh
bash scripts/claude_usage.sh --powerline
```

---

## Local mode accuracy

Local mode uses hardcoded plan limits (Pro: $18, Max5: $35, Max20: $140 per 5h window) and hardcoded model pricing. Both are community-sourced and can drift if Anthropic changes them. The `~` is intentional - it means "close enough to be useful, not precise enough to trust blindly." For exact numbers, set up a session key.
