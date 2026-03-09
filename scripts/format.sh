#!/usr/bin/env bash
# format.sh - format Claude usage data into a tmux status bar string.
#
# Reads CLAUDE_* environment variables set by fetch_usage.sh.
# Call as a function (after sourcing) or as a standalone script.
#
# Usage as script:
#   format_output [--powerline]
#
# --powerline : omit inline tmux color codes (powerline handles its own styling)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

# ---------------------------------------------------------------------------
# Gauge bar
# ---------------------------------------------------------------------------
build_gauge() {
    local pct="$1"
    local width="${2:-10}"
    local filled
    filled=$(awk "BEGIN { printf \"%d\", int(($pct / 100) * $width + 0.5) }")
    (( filled > width )) && filled=$width
    local empty=$(( width - filled ))
    local gauge="" i
    for (( i=0; i<filled; i++ )); do gauge+="▰"; done
    for (( i=0; i<empty;  i++ )); do gauge+="▱"; done
    echo "$gauge"
}

# ---------------------------------------------------------------------------
# Color selection
# ---------------------------------------------------------------------------
get_color() {
    local pct="$1"
    local warn high crit
    warn=$(get_tmux_option "@claude_usage_threshold_warn" "60")
    high=$(get_tmux_option "@claude_usage_threshold_high" "80")
    crit=$(get_tmux_option "@claude_usage_threshold_crit" "95")

    if   (( pct >= crit )); then get_tmux_option "@claude_usage_color_crit"   "colour196"
    elif (( pct >= high )); then get_tmux_option "@claude_usage_color_high"   "colour208"
    elif (( pct >= warn )); then get_tmux_option "@claude_usage_color_warn"   "colour220"
    else                         get_tmux_option "@claude_usage_color_normal" "colour82"
    fi
}

# ---------------------------------------------------------------------------
# Tier rendering
# ---------------------------------------------------------------------------

# _tier_str PCT RESET_EPOCH APPROX SHOW_GAUGE [ALLOW_RESET]
# Returns a string like "▰▰▰▱▱▱▱▱▱▱ ~42%" or "~42%" or "42% RESET 2h3m"
# ALLOW_RESET=0 suppresses the reset countdown (used by minimal preset).
_tier_str() {
    local pct="$1"
    local reset_epoch="${2:-}"
    local approx="${3:-1}"
    local show_gauge="${4:-0}"
    local allow_reset="${5:-1}"

    local crit_threshold
    crit_threshold=$(get_tmux_option "@claude_usage_threshold_crit" "95")

    # Approximate prefix
    local pfx=""
    [[ "$approx" == "1" ]] && pfx="~"

    # Reset countdown - shown based on @claude_usage_show_reset option:
    #   auto   (default) - only when pct >= crit threshold
    #   always           - whenever reset time is available (API mode only)
    local reset_str=""
    local show_reset_opt
    show_reset_opt=$(get_tmux_option "@claude_usage_show_reset" "auto")
    if [[ "$allow_reset" == "1" && -n "$reset_epoch" && "$reset_epoch" != "0" ]]; then
        local now secs_left
        now=$(current_epoch)
        secs_left=$(( reset_epoch - now ))
        if (( secs_left > 0 )); then
            if [[ "$show_reset_opt" == "always" || "$pct" -ge "$crit_threshold" ]]; then
                reset_str=" RESET $(format_countdown "$secs_left")"
            fi
        fi
    fi

    if [[ "$show_gauge" == "1" ]]; then
        local gauge_width
        gauge_width=$(get_tmux_option "@claude_usage_gauge_width" "10")
        local gauge
        gauge=$(build_gauge "$pct" "$gauge_width")
        echo "${gauge} ${pfx}${pct}%${reset_str}"
    else
        echo "${pfx}${pct}%${reset_str}"
    fi
}

# ---------------------------------------------------------------------------
# Main formatter
# ---------------------------------------------------------------------------
format_output() {
    local powerline=""

    # Legacy positional-arg interface (used by tests and direct invocation):
    #   format_output PCT [APPROX] [--powerline]
    # If the first arg looks like a number, treat it as PCT and inject env vars.
    if [[ "${1:-}" =~ ^-?[0-9]+$ ]]; then
        local _pct="$1"; shift
        local _approx=1
        if [[ "${1:-}" =~ ^[01]$ ]]; then
            _approx="$1"; shift
        fi
        [[ "${1:-}" == "--powerline" ]] && powerline="--powerline"
        # Inject into env so the rest of the function reads consistently
        export CLAUDE_SOURCE="${CLAUDE_SOURCE:-local}"
        export CLAUDE_APPROX="$_approx"
        export CLAUDE_5H_PCT="$_pct"
        export CLAUDE_5H_RESET="${CLAUDE_5H_RESET:-}"
        export CLAUDE_7D_PCT="${CLAUDE_7D_PCT:--1}"
        export CLAUDE_7D_RESET="${CLAUDE_7D_RESET:-}"
        export CLAUDE_7D_OPUS_PCT="${CLAUDE_7D_OPUS_PCT:--1}"
        export CLAUDE_7D_SONNET_PCT="${CLAUDE_7D_SONNET_PCT:--1}"
        export CLAUDE_ERROR="${CLAUDE_ERROR:-}"
    else
        [[ "${1:-}" == "--powerline" ]] && powerline="--powerline"
    fi

    local icon label fmt
    icon=$(get_tmux_option "@claude_usage_icon"  "󰚩")
    label=$(get_tmux_option "@claude_usage_label" "Claude")
    # Display presets (set via @claude_usage_format):
    #   compact  (default) - 󰚩 Claude 5h:18% 7d:2%     multi-tier, no bar
    #   gauge              - 󰚩 Claude ▰▰▰▰▱▱▱▱▱▱ ~18%  visual bar, primary tier only
    #   minimal            - 󰚩 ~18%                     icon + pct, no label/tier prefix
    fmt=$(get_tmux_option "@claude_usage_format" "compact")

    # Read fetch output variables (set in environment by caller)
    local src="${CLAUDE_SOURCE:-local}"
    local approx="${CLAUDE_APPROX:-1}"
    local fh_pct="${CLAUDE_5H_PCT:--1}"
    local fh_reset="${CLAUDE_5H_RESET:-}"
    local sd_pct="${CLAUDE_7D_PCT:--1}"
    local sd_reset="${CLAUDE_7D_RESET:-}"
    local opus_pct="${CLAUDE_7D_OPUS_PCT:--1}"
    local sonnet_pct="${CLAUDE_7D_SONNET_PCT:--1}"
    local err="${CLAUDE_ERROR:-}"

    # Hard error / no data at all
    if [[ "$fh_pct" == "-1" && "$sd_pct" == "-1" ]]; then
        local no_data_text="${icon}"
        if [[ "$fmt" != "minimal" ]]; then
            [[ -n "$label" ]] && no_data_text+=" ${label}"
        fi
        if [[ "$err" == "session_expired" ]]; then
            no_data_text+=" KEY?"
        else
            no_data_text+=" --"
        fi
        if [[ "$powerline" == "--powerline" ]]; then
            echo "#[fg=colour244]${no_data_text}"
        else
            echo "#[fg=colour244]${no_data_text}#[default]"
        fi
        return
    fi

    # Decide which tiers to show.
    # "auto" (default): show all tiers with non-null data from the API.
    # Explicit list: "5h 7d 7d_sonnet" etc.
    local tiers_cfg
    tiers_cfg=$(get_tmux_option "@claude_usage_tiers" "auto")
    local tiers=()
    if [[ "$tiers_cfg" == "auto" ]]; then
        [[ "$fh_pct"     -ge 0 ]] && tiers+=("5h")
        [[ "$sd_pct"     -ge 0 ]] && tiers+=("7d")
        [[ "$sonnet_pct" -ge 0 ]] && tiers+=("7d_sonnet")
        [[ "$opus_pct"   -ge 0 ]] && tiers+=("7d_opus")
    else
        read -ra tiers <<< "$tiers_cfg"
    fi

    # Determine primary color (based on 5h pct, or 7d if 5h unavailable)
    local primary_pct="$fh_pct"
    (( primary_pct < 0 )) && primary_pct="$sd_pct"
    (( primary_pct < 0 )) && primary_pct=0
    local color
    color=$(get_color "$primary_pct")

    # Per-preset rendering flags
    local show_gauge=0    # show ▰▰▰▱▱▱ bar
    local show_prefix=1   # show "5h:" / "7d:" tier labels
    local primary_only=0  # only render the first available tier
    local allow_reset=1   # show reset countdown (suppressed in minimal)

    case "$fmt" in
        gauge)
            show_gauge=1; show_prefix=0; primary_only=1; allow_reset=1 ;;
        minimal)
            show_gauge=0; show_prefix=0; primary_only=1; allow_reset=0 ;;
        compact|*)
            show_gauge=0; show_prefix=1; primary_only=0; allow_reset=1 ;;
    esac

    # Build segment parts
    local parts=()

    for tier in "${tiers[@]}"; do
        [[ "$primary_only" == "1" && "${#parts[@]}" -gt 0 ]] && break

        local pfx=""
        [[ "$show_prefix" == "1" ]] && case "$tier" in
            5h)        pfx="5h:"   ;;
            7d)        pfx="7d:"   ;;
            7d_opus)   pfx="opus:" ;;
            7d_sonnet) pfx="snt:"  ;;
        esac

        case "$tier" in
            5h)
                [[ "$fh_pct" -lt 0 ]] && continue
                parts+=("${pfx}$(_tier_str "$fh_pct" "$fh_reset" "$approx" "$show_gauge" "$allow_reset")")
                ;;
            7d)
                [[ "$sd_pct" -lt 0 ]] && continue
                parts+=("${pfx}$(_tier_str "$sd_pct" "$sd_reset" "$approx" "0" "$allow_reset")")
                ;;
            7d_opus)
                [[ "$opus_pct" -lt 0 ]] && continue
                parts+=("${pfx}$(_tier_str "$opus_pct" "${CLAUDE_7D_OPUS_RESET:-}" "$approx" "0" "$allow_reset")")
                ;;
            7d_sonnet)
                [[ "$sonnet_pct" -lt 0 ]] && continue
                parts+=("${pfx}$(_tier_str "$sonnet_pct" "${CLAUDE_7D_SONNET_RESET:-}" "$approx" "0" "$allow_reset")")
                ;;
        esac
    done

    # Nothing to show
    if [[ ${#parts[@]} -eq 0 ]]; then
        local empty_text="${icon}"
        if [[ "$fmt" != "minimal" ]]; then
            [[ -n "$label" ]] && empty_text+=" ${label} --"
        else
            empty_text+=" --"
        fi
        if [[ "$powerline" == "--powerline" ]]; then
            echo "#[fg=colour244]${empty_text}"
        else
            echo "#[fg=colour244]${empty_text}#[default]"
        fi
        return
    fi

    # Assemble
    local body
    body=$(IFS=' '; echo "${parts[*]}")

    local text="${icon}"
    if [[ "$fmt" != "minimal" ]]; then
        [[ -n "$label" ]] && text+=" ${label}"
    fi
    text+=" ${body}"

    if [[ "$powerline" == "--powerline" ]]; then
        # Include fg color code so tmux-powerline's fixed segment color doesn't
        # override it. No trailing #[default] - powerline handles reset itself.
        echo "#[fg=${color}]${text}"
    else
        echo "#[fg=${color}]${text}#[default]"
    fi
}

# Run as a script when not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    format_output "$@"
fi
