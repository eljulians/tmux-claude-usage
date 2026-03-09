#!/usr/bin/env bash
# claude_usage.sh - main entry point called by tmux #(...) every status-interval.
#
# Fast path: read from cache if fresh.
# Slow path: fetch + format, write to cache, print.
#
# Flags:
#   --powerline   omit inline tmux color codes (for tmux-powerline segment)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

POWERLINE_FLAG=""
for arg in "$@"; do
    [[ "$arg" == "--powerline" ]] && POWERLINE_FLAG="--powerline"
done

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------
CACHE_SUFFIX=""
[[ -n "$POWERLINE_FLAG" ]] && CACHE_SUFFIX="-pl"
CACHE_FILE="/tmp/tmux-claude-usage-${UID}${CACHE_SUFFIX}.cache"
CACHE_TTL=$(get_tmux_option "@claude_usage_cache_seconds" "60")

if [[ -f "$CACHE_FILE" ]]; then
    cache_mtime=$(stat_mtime "$CACHE_FILE")
    if [[ -n "$cache_mtime" ]]; then
        cache_age=$(( $(current_epoch) - cache_mtime ))
        if (( cache_age < CACHE_TTL )); then
            cat "$CACHE_FILE"
            exit 0
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Fetch - sets CLAUDE_* variables in this shell
# ---------------------------------------------------------------------------
CLAUDE_SOURCE="local"
CLAUDE_APPROX=1
CLAUDE_PCT=-1
CLAUDE_5H_PCT=-1
CLAUDE_5H_RESET=""
CLAUDE_7D_PCT=-1
CLAUDE_7D_RESET=""
CLAUDE_7D_OPUS_PCT=-1
CLAUDE_7D_OPUS_RESET=""
CLAUDE_7D_SONNET_PCT=-1
CLAUDE_7D_SONNET_RESET=""
CLAUDE_ERROR=""

eval "$("${SCRIPT_DIR}/fetch_usage.sh" 2>/dev/null)" || true

# ---------------------------------------------------------------------------
# Format - reads CLAUDE_* from environment
# ---------------------------------------------------------------------------
source "${SCRIPT_DIR}/format.sh"
output=$(format_output "$POWERLINE_FLAG" 2>/dev/null)

# Write cache and print
printf '%s' "$output" > "$CACHE_FILE"
printf '%s' "$output"
