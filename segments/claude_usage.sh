#!/usr/bin/env bash
# segments/claude_usage.sh - tmux-powerline segment for Claude usage.
#
# Drop this file into your tmux-powerline segments directory:
#   cp segments/claude_usage.sh ~/.config/tmux-powerline/segments/
#
# Then add to your powerline theme's right segments array:
#   "claude_usage 235 82 $powerline_right_arrow_symbol 0"

# Locate the plugin root: prefer the canonical TPM location, fall back to
# the directory two levels above this segment file (in-repo usage).
_PLUGIN_ROOT="${HOME}/.tmux/plugins/tmux-claude-usage"
if [[ ! -d "$_PLUGIN_ROOT" ]]; then
    _PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Called by tmux-powerline to generate the segment's default config file.
generate_segmentrc() {
    read -r -d '' rccontents << 'EORC' || true
# Claude usage segment configuration.
# Tiers to show: 5h (more tiers require web API session key)
export TMUX_POWERLINE_SEG_CLAUDE_USAGE_TIERS="${TMUX_POWERLINE_SEG_CLAUDE_USAGE_TIERS:-5h}"
# Cache seconds (matches @claude_usage_cache_seconds if set)
export TMUX_POWERLINE_SEG_CLAUDE_USAGE_CACHE="${TMUX_POWERLINE_SEG_CLAUDE_USAGE_CACHE:-60}"
EORC
    echo "$rccontents"
}

# Called by tmux-powerline every refresh to produce segment output.
# Powerline handles colors and separators; we emit plain text.
run_segment() {
    local script="${_PLUGIN_ROOT}/scripts/claude_usage.sh"
    if [[ ! -x "$script" ]]; then
        return 1
    fi
    "$script" --powerline
    return $?
}

# Allow direct invocation for testing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_segment
fi
