# tmux-claude-usage

[![tests](https://github.com/eljulians/tmux-claude-usage/actions/workflows/test.yml/badge.svg)](https://github.com/eljulians/tmux-claude-usage/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![tmux](https://img.shields.io/badge/tmux-3.0+-1bb91f.svg)](https://github.com/tmux/tmux)
[![bash](https://img.shields.io/badge/bash-4.0+-4EAA25.svg?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey.svg)](#requirements)

Your Claude Code usage limits in the tmux status bar.

```
󰚩 Claude 5h:26% 7d:3% snt:8%   # compact (default) - all available tiers
󰚩 Claude ▰▰▰▱▱▱▱▱▱▱ ~26%       # gauge
󰚩 ~26%                          # minimal
```

No switching to the web console. Color-coded at a glance. Zero config to start.

---

## Two modes: local (default) vs exact

| | Approximate (local) | Exact (web API) |
|---|---|---|
| **Setup** | None - works immediately | Paste a browser session key once |
| **Data source** | `~/.claude/projects/` JSONL files | Claude.ai web API |
| **Accuracy** | Approximate (`~26%`) | Exact (`26%`) |
| **Tiers shown** | 5h only | All tiers your plan has (5h, 7d, per-model) |
| **Reset times** | Not available | Configurable - at limit or always |

**The `~` prefix means approximate.** Local mode estimates cost from raw token counts using community-sourced price tables. In practice it can be off by 10-20 percentage points - good enough for "am I close to the limit?" but not something to trust when you're at 80% and wondering if you have headroom.

**Why is it off?** Anthropic's actual usage accounting is opaque. The plugin estimates cost from token counts × hardcoded model prices, but Anthropic may apply discounts, rounding, or count tokens differently (e.g. tool use overhead). The plan limits themselves ($18/$35/$140 per 5h) are community-estimated, not official.

**No `~` means exact.** The session key lets the plugin hit the same internal API the Claude.ai dashboard uses, so the numbers match what Anthropic actually counts. This is the only way to get accurate numbers - the Claude Code OAuth token (`~/.claude/.credentials.json`) only has `user:inference` scope and can't access usage data.

The session key is entirely optional. If you never set it you get local mode forever.

To configure exact mode, see [exact mode setup](#exact-mode-setup).

---

## Features

- **Zero-setup default** - reads local Claude Code data, no credentials needed
- **Optional exact mode** - add a browser session key for precise numbers
- **Auto tier detection** - shows all tiers your plan provides (5h, 7d, per-model sonnet/opus)
- **Color temperature** - green → yellow → orange → red as usage climbs
- **Configurable reset countdown** - always visible or only near the limit
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
set -g @plugin 'eljulians/tmux-claude-usage'

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
# Copy the segment to the user segments directory (create if needed)
mkdir -p ~/.config/tmux-powerline/segments/
cp segments/claude_usage.sh ~/.config/tmux-powerline/segments/

# Add to your powerline theme's right segments array.
# Use default_fg_color so the segment's own color coding takes effect:
# "claude_usage 235 default_fg_color default_separator no_sep_bg_color no_sep_fg_color no_spacing_disable separator_disable"
```

---

## Configuration

All options are optional - defaults work out of the box.

```tmux
# ~/.tmux.conf

# Display preset:
#   compact  (default) - 󰚩 Claude 5h:26% 7d:3% snt:8%   multi-tier, no bar
#   gauge              - 󰚩 Claude ▰▰▰▱▱▱▱▱▱▱ ~26%        visual bar, primary tier
#   minimal            - 󰚩 ~26%                           icon + pct only
set -g @claude_usage_format "compact"

# Tiers to display.
# "auto" (default) shows all tiers with data from the API.
# Explicit list overrides: "5h 7d 7d_sonnet 7d_opus"
set -g @claude_usage_tiers "auto"

# Reset countdown visibility (compact and gauge presets only, never in minimal):
#   auto   (default) - only shown when usage is at/near the critical threshold
#   always           - always shown when available (requires API/exact mode)
set -g @claude_usage_show_reset "auto"

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

### Keeping the session key out of version control

If your `tmux.conf` is in a public dotfiles repo, store the key in a gitignored secrets file instead:

```bash
# ~/secrets.sh  (gitignored)
export CLAUDE_SESSION_KEY="sk-ant-sid01-..."
```

```bash
# ~/.zshrc or ~/.bashrc
source ~/secrets.sh
```

```tmux
# ~/.tmux.conf - references the env var, safe to commit
set -g @claude_usage_session_key "$CLAUDE_SESSION_KEY"
```

The plugin expands `$VAR_NAME` and `${VAR_NAME}` references in the tmux option, and also checks `CLAUDE_USAGE_SESSION_KEY` directly if the option is unset.

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

Local mode uses hardcoded plan limits (Pro: $18, Max5: $35, Max20: $140 per 5h window) and hardcoded model pricing (Opus $15/$75, Sonnet $3/$15, Haiku $0.25/$1.25 per 1M input/output tokens). Both are community-sourced and can drift if Anthropic changes them.

Expect **±10-20 percentage points** versus what the dashboard shows. The gap comes from:
- Anthropic's actual counting method being undocumented
- Tool use and system prompt tokens being accounted differently
- Plan limits being estimated, not confirmed

The `~` is intentional. Set up a session key if you need precision.
