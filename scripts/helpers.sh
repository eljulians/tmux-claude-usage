#!/usr/bin/env bash
# helpers.sh - shared utilities for tmux-claude-usage
# Sourced by other scripts; never executed directly.

# Read a tmux global option, returning default_value if unset or tmux unavailable.
get_tmux_option() {
    local option="$1"
    local default_value="${2:-}"
    local value
    value=$(tmux show-option -gqv "$option" 2>/dev/null)
    if [[ -z "$value" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# True if running on macOS.
is_osx() {
    [[ "$(uname)" == "Darwin" ]]
}

# Current epoch seconds. Override with CLAUDE_USAGE_TEST_NOW in tests.
current_epoch() {
    if [[ -n "${CLAUDE_USAGE_TEST_NOW:-}" ]]; then
        echo "$CLAUDE_USAGE_TEST_NOW"
    else
        date +%s
    fi
}

# Epoch seconds for N hours ago.
hours_ago_epoch() {
    local hours="$1"
    local now
    now=$(current_epoch)
    echo $(( now - hours * 3600 ))
}

# Cross-platform file mtime in epoch seconds.
stat_mtime() {
    local file="$1"
    if is_osx; then
        stat -f%m "$file" 2>/dev/null
    else
        stat -c%Y "$file" 2>/dev/null
    fi
}

# Convert an ISO 8601 timestamp to epoch seconds.
# Handles: 2026-03-09T14:00:00.297687+00:00  and  2026-03-09T14:00:00Z
iso_to_epoch() {
    local ts="${1:-}"
    [[ -z "$ts" ]] && return 1

    # Normalise to a form `date` can parse on both Linux and macOS:
    # strip subseconds, convert +00:00 → Z
    local norm
    norm=$(echo "$ts" | sed 's/\.[0-9]*//' | sed 's/+00:00$/Z/')

    if is_osx; then
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$norm" +%s 2>/dev/null
    else
        date -d "$norm" +%s 2>/dev/null
    fi
}

# Format a seconds-from-now duration into a human-readable countdown.
# e.g. 7380 → "2h3m", 90 → "1m", 45 → "45s", ≤0 → "now"
format_countdown() {
    local secs="${1:-0}"
    if   (( secs <= 0   )); then echo "now"
    elif (( secs < 60   )); then echo "${secs}s"
    elif (( secs < 3600 )); then echo "$(( secs / 60 ))m"
    else
        local h=$(( secs / 3600 ))
        local m=$(( (secs % 3600) / 60 ))
        if (( m == 0 )); then echo "${h}h"
        else                   echo "${h}h${m}m"
        fi
    fi
}

# Map a Claude model name to a pricing tier: opus | haiku | sonnet (default).
model_to_tier() {
    local model="${1:-}"
    case "$model" in
        *opus*)  echo "opus"   ;;
        *haiku*) echo "haiku"  ;;
        *)       echo "sonnet" ;;
    esac
}

# Plan cost limits (USD) per 5-hour window.
plan_cost_limit() {
    case "${1:-pro}" in
        pro)   echo "18.0"  ;;
        max5)  echo "35.0"  ;;
        max20) echo "140.0" ;;
        *)     echo ""      ;;
    esac
}

# Detect plan type from ~/.claude/.credentials.json.
# Checks both subscriptionType and rateLimitTier fields.
# Prints: pro | max5 | max20 | pro (fallback)
detect_plan() {
    local creds_file="${HOME}/.claude/.credentials.json"
    if [[ ! -f "$creds_file" ]]; then
        echo "pro"
        return
    fi

    local sub_type rate_tier
    if command -v jq &>/dev/null; then
        sub_type=$(jq -r '.claudeAiOauth.subscriptionType // ""' "$creds_file" 2>/dev/null)
        rate_tier=$(jq -r '.claudeAiOauth.rateLimitTier // ""' "$creds_file" 2>/dev/null)
    else
        read -r sub_type rate_tier < <(python3 -c "
import json
try:
    d = json.load(open('${creds_file}'))
    o = d.get('claudeAiOauth', {})
    print(o.get('subscriptionType', ''), o.get('rateLimitTier', ''))
except:
    print('', '')
" 2>/dev/null)
    fi

    # Combine both fields - whichever contains plan info wins
    local combined="${sub_type} ${rate_tier}"
    case "$combined" in
        *max*20*|*20x*) echo "max20" ;;
        *max*5*|*5x*)   echo "max5"  ;;
        *)               echo "pro"  ;;
    esac
}
