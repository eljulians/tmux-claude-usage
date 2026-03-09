# Changelog

## v0.2.0

### New Features

- **All your plan's tiers shown automatically** — the plugin now detects which usage limits your plan has (5-hour, 7-day, per-model) and displays all of them without any configuration. Max 5x users with a Sonnet-only weekly limit will see it appear automatically.

- **Reset countdown always visible** — you can now show the time until your limit resets at all times, not only when you're near the limit. Set `@claude_usage_show_reset "always"` to enable it.

- **Session key from environment variable** — store your session key in a gitignored secrets file and reference it safely from your public dotfiles. The plugin expands `$VAR_NAME` references in the config option and also reads `CLAUDE_USAGE_SESSION_KEY` directly from the environment.

### Bug Fixes

- **Fixed wrong color in tmux-powerline** — the status bar segment was always green regardless of usage level when using tmux-powerline. It now correctly turns yellow, orange, and red as usage climbs.

---

## v0.1.0

Initial release. Local JSONL parsing, cost-based usage estimation, three display presets (compact, gauge, minimal), color thresholds, TPM and tmux-powerline integration, optional exact mode via Claude.ai web API session key.
