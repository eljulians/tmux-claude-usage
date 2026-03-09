#!/usr/bin/env bash
# fetch_usage.sh - fetch Claude usage data and print shell-eval-safe variables.
#
# Output variables (one per line, KEY=VALUE):
#   CLAUDE_SOURCE          "api" | "local"
#   CLAUDE_APPROX          0 = exact (API)  |  1 = approximate (local)
#   CLAUDE_PCT             primary percentage for backward compat (= 5h pct)
#   CLAUDE_5H_PCT          5-hour utilization, 0-100, or -1 if unavailable
#   CLAUDE_5H_RESET        epoch of 5h window reset, or "" if unknown
#   CLAUDE_7D_PCT          7-day utilization, or -1
#   CLAUDE_7D_RESET        epoch of 7d window reset, or ""
#   CLAUDE_7D_OPUS_PCT     7-day Opus utilization, or -1
#   CLAUDE_7D_OPUS_RESET   epoch, or ""
#   CLAUDE_7D_SONNET_PCT   7-day Sonnet utilization, or -1
#   CLAUDE_7D_SONNET_RESET epoch, or ""
#   CLAUDE_ERROR           non-empty on hard error
#
# Usage:
#   eval "$(fetch_usage.sh)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_emit() {
    # Print all CLAUDE_* variables in eval-safe form.
    echo "CLAUDE_SOURCE=${CLAUDE_SOURCE}"
    echo "CLAUDE_APPROX=${CLAUDE_APPROX}"
    echo "CLAUDE_PCT=${CLAUDE_5H_PCT}"
    echo "CLAUDE_5H_PCT=${CLAUDE_5H_PCT}"
    echo "CLAUDE_5H_RESET=${CLAUDE_5H_RESET}"
    echo "CLAUDE_7D_PCT=${CLAUDE_7D_PCT}"
    echo "CLAUDE_7D_RESET=${CLAUDE_7D_RESET}"
    echo "CLAUDE_7D_OPUS_PCT=${CLAUDE_7D_OPUS_PCT}"
    echo "CLAUDE_7D_OPUS_RESET=${CLAUDE_7D_OPUS_RESET}"
    echo "CLAUDE_7D_SONNET_PCT=${CLAUDE_7D_SONNET_PCT}"
    echo "CLAUDE_7D_SONNET_RESET=${CLAUDE_7D_SONNET_RESET}"
    echo "CLAUDE_ERROR=${CLAUDE_ERROR}"
}

# Defaults
CLAUDE_SOURCE="local"
CLAUDE_APPROX=1
CLAUDE_5H_PCT=-1
CLAUDE_5H_RESET=""
CLAUDE_7D_PCT=-1
CLAUDE_7D_RESET=""
CLAUDE_7D_OPUS_PCT=-1
CLAUDE_7D_OPUS_RESET=""
CLAUDE_7D_SONNET_PCT=-1
CLAUDE_7D_SONNET_RESET=""
CLAUDE_ERROR=""

# ---------------------------------------------------------------------------
# API mode
# ---------------------------------------------------------------------------

# _pct_int FLOAT → integer 0-100
_pct_int() {
    local v="${1:-0}"
    awk "BEGIN { v=int($v+0.5); if(v>100)v=100; if(v<0)v=0; print v }"
}

# _reset_epoch ISO_STRING → epoch or ""
_reset_epoch() {
    local ts="${1:-}"
    [[ -z "$ts" || "$ts" == "null" ]] && return 0
    iso_to_epoch "$ts"
}

_fetch_from_api() {
    local session_key="$1"
    local org_id

    # Allow test override of org ID
    org_id=$(get_tmux_option "@claude_usage_org_id" "")
    if [[ -z "$org_id" && -n "${CLAUDE_USAGE_TEST_ORG_ID:-}" ]]; then
        org_id="$CLAUDE_USAGE_TEST_ORG_ID"
    fi

    if [[ -z "$org_id" ]]; then
        org_id=$(_discover_org_id "$session_key") || true
        if [[ -z "$org_id" ]]; then
            CLAUDE_ERROR="org_discovery_failed"
            return 1
        fi
        # Cache org ID in tmux (best-effort; may fail outside tmux)
        tmux set-option -gq "@claude_usage_org_id" "$org_id" 2>/dev/null || true
    fi

    local body http_code
    local response
    response=$(curl -s -w $'\n%{http_code}' \
        "https://claude.ai/api/organizations/${org_id}/usage" \
        -H "Cookie: sessionKey=${session_key}" \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
        -H "Accept: application/json" \
        -H "Referer: https://claude.ai/" \
        -H "Origin: https://claude.ai" \
        -H "Anthropic-Client-Platform: web_claude_ai" \
        2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    # Detect non-JSON (Cloudflare HTML intercept)
    if [[ "$body" == *"<!DOCTYPE"* || "$body" == *"<html"* ]]; then
        CLAUDE_ERROR="cloudflare_blocked"
        return 1
    fi

    if [[ "$http_code" == "401" ]]; then
        CLAUDE_ERROR="session_expired"
        return 1
    fi

    if [[ "$http_code" != "200" ]]; then
        CLAUDE_ERROR="http_${http_code}"
        return 1
    fi

    # Parse JSON with jq or python3
    if command -v jq &>/dev/null; then
        _parse_api_json_jq "$body"
    elif command -v python3 &>/dev/null; then
        _parse_api_json_python3 "$body"
    else
        CLAUDE_ERROR="no_parser"
        return 1
    fi

    CLAUDE_SOURCE="api"
    CLAUDE_APPROX=0
    return 0
}

_discover_org_id() {
    local session_key="$1"
    local body http_code response
    response=$(curl -s -w $'\n%{http_code}' \
        "https://claude.ai/api/organizations" \
        -H "Cookie: sessionKey=${session_key}" \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
        -H "Accept: application/json" \
        -H "Referer: https://claude.ai/" \
        -H "Origin: https://claude.ai" \
        -H "Anthropic-Client-Platform: web_claude_ai" \
        2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    [[ "$http_code" != "200" ]] && return 1

    if command -v jq &>/dev/null; then
        jq -r '.[0].uuid // empty' <<< "$body" 2>/dev/null
    else
        python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    print(data[0]['uuid'])
except:
    pass
" <<< "$body" 2>/dev/null
    fi
}

_parse_api_json_jq() {
    local body="$1"
    # One value per line to avoid TSV tab-collapsing when fields are empty.
    # Use while-read instead of mapfile for bash 3.x compatibility (macOS /bin/bash).
    local fields=()
    local _line
    while IFS= read -r _line; do
        fields+=("$_line")
    done < <(jq -r '
        def pct(x): if x == null then -1 else (x | if . > 100 then 100 elif . < 0 then 0 else . end | floor) end;
        def rst(x): if x == null then "" else x end;
        pct(.five_hour.utilization),
        rst(.five_hour.resets_at),
        pct(.seven_day.utilization),
        rst(.seven_day.resets_at),
        pct(.seven_day_opus.utilization),
        rst(.seven_day_opus.resets_at),
        pct(.seven_day_sonnet.utilization),
        rst(.seven_day_sonnet.resets_at)
    ' <<< "$body" 2>/dev/null)

    [[ ${#fields[@]} -lt 8 ]] && return 1

    CLAUDE_5H_PCT="${fields[0]}"
    CLAUDE_7D_PCT="${fields[2]}"
    CLAUDE_7D_OPUS_PCT="${fields[4]}"
    CLAUDE_7D_SONNET_PCT="${fields[6]}"

    CLAUDE_5H_RESET=$(_reset_epoch "${fields[1]}") || CLAUDE_5H_RESET=""
    CLAUDE_7D_RESET=$(_reset_epoch "${fields[3]}") || CLAUDE_7D_RESET=""
    CLAUDE_7D_OPUS_RESET=$(_reset_epoch "${fields[5]}") || CLAUDE_7D_OPUS_RESET=""
    CLAUDE_7D_SONNET_RESET=$(_reset_epoch "${fields[7]}") || CLAUDE_7D_SONNET_RESET=""
}

_parse_api_json_python3() {
    local body="$1"
    # Use env var to pass body - avoids heredoc/stdin conflict and escaping issues.
    # Output one value per line (like jq path) to avoid IFS tab-collapse bug.
    local fields=()
    local _line
    while IFS= read -r _line; do
        fields+=("$_line")
    done < <(CLAUDE_USAGE_JSON_BODY="$body" python3 - <<'PYEOF'
import json, os

def pct(x):
    if x is None: return -1
    return min(100, max(0, int(x)))

def raw_ts(x):
    # Return the raw ISO string so bash iso_to_epoch handles conversion,
    # matching jq's rst() output format.
    return x or ""

try:
    data = json.loads(os.environ['CLAUDE_USAGE_JSON_BODY'])
    fh = data.get('five_hour') or {}
    sd = data.get('seven_day') or {}
    op = data.get('seven_day_opus') or {}
    sn = data.get('seven_day_sonnet') or {}
    values = [
        str(pct(fh.get('utilization'))),
        raw_ts(fh.get('resets_at')),
        str(pct(sd.get('utilization'))),
        raw_ts(sd.get('resets_at')),
        str(pct(op.get('utilization'))),
        raw_ts(op.get('resets_at')),
        str(pct(sn.get('utilization'))),
        raw_ts(sn.get('resets_at')),
    ]
    print('\n'.join(values))
except Exception:
    for i in range(8):
        print('-1' if i % 2 == 0 else '')
PYEOF
    )

    [[ ${#fields[@]} -lt 8 ]] && return 1

    CLAUDE_5H_PCT="${fields[0]}"
    CLAUDE_7D_PCT="${fields[2]}"
    CLAUDE_7D_OPUS_PCT="${fields[4]}"
    CLAUDE_7D_SONNET_PCT="${fields[6]}"

    CLAUDE_5H_RESET=$(_reset_epoch "${fields[1]}") || CLAUDE_5H_RESET=""
    CLAUDE_7D_RESET=$(_reset_epoch "${fields[3]}") || CLAUDE_7D_RESET=""
    CLAUDE_7D_OPUS_RESET=$(_reset_epoch "${fields[5]}") || CLAUDE_7D_OPUS_RESET=""
    CLAUDE_7D_SONNET_RESET=$(_reset_epoch "${fields[7]}") || CLAUDE_7D_SONNET_RESET=""
}

# ---------------------------------------------------------------------------
# Local JSONL mode
# ---------------------------------------------------------------------------

_fetch_from_local() {
    local projects_dir="$1"
    local window_start="$2"
    local plan="$3"

    local limit
    limit=$(plan_cost_limit "$plan")
    if [[ -z "$limit" ]]; then
        CLAUDE_ERROR="unknown_plan"
        return 1
    fi

    local jsonl_files=()
    while IFS= read -r f; do
        jsonl_files+=("$f")
    done < <(find "$projects_dir" -name '*.jsonl' 2>/dev/null)

    if [[ ${#jsonl_files[@]} -eq 0 ]]; then
        CLAUDE_5H_PCT=0
        return 0
    fi

    local total_cost
    if command -v jq &>/dev/null; then
        total_cost=$(_local_cost_jq "${jsonl_files[@]}" "$window_start")
    elif command -v python3 &>/dev/null; then
        total_cost=$(_local_cost_python3 "$projects_dir" "$window_start")
    else
        CLAUDE_ERROR="no_parser"
        return 1
    fi

    CLAUDE_5H_PCT=$(awk "BEGIN { v = ($total_cost / $limit) * 100; if (v > 100) v = 100; printf \"%d\", v }")
    CLAUDE_APPROX=1
    CLAUDE_SOURCE="local"
}

_local_cost_jq() {
    local window_start="${@: -1}"
    local files=("${@:1:$#-1}")

    for f in "${files[@]}"; do
        jq -r --argjson start "$window_start" '
            select(.type == "assistant")
            | select(.message.usage != null)
            | select(
                (.timestamp
                 | gsub("\\.\\d+Z$"; "Z")
                 | fromdateiso8601) >= $start
              )
            | [
                (.message.id // ""),
                (.message.model // "claude-sonnet-4-6"),
                (.message.usage.input_tokens              // 0),
                (.message.usage.output_tokens             // 0),
                (.message.usage.cache_creation_input_tokens // 0),
                (.message.usage.cache_read_input_tokens   // 0)
              ] | @tsv
        ' "$f" 2>/dev/null
    done \
    | sort -u -k1,1 \
    | awk -v FS='\t' '
        BEGIN { total = 0 }
        {
            model=$2; inp=$3+0; out=$4+0; cc=$5+0; cr=$6+0
            if      (model ~ /opus/)  { ip=15.0;  op=75.0;  cp=18.75; rp=1.5  }
            else if (model ~ /haiku/) { ip=0.25;  op=1.25;  cp=0.3;   rp=0.03 }
            else                      { ip=3.0;   op=15.0;  cp=3.75;  rp=0.3  }
            total += (inp/1e6)*ip + (out/1e6)*op + (cc/1e6)*cp + (cr/1e6)*rp
        }
        END { printf "%.8f", total }
    '
}

_local_cost_python3() {
    local projects_dir="$1"
    local window_start="$2"

    python3 - "$projects_dir" "$window_start" <<'PYEOF'
import json, os, sys

projects_dir = sys.argv[1]
window_start = int(sys.argv[2])

PRICING = {
    'opus':   {'i': 15.0,  'o': 75.0,  'cc': 18.75, 'cr': 1.5  },
    'sonnet': {'i': 3.0,   'o': 15.0,  'cc': 3.75,  'cr': 0.3  },
    'haiku':  {'i': 0.25,  'o': 1.25,  'cc': 0.3,   'cr': 0.03 },
}

def get_tier(model):
    if 'opus'  in (model or ''): return 'opus'
    if 'haiku' in (model or ''): return 'haiku'
    return 'sonnet'

def parse_epoch(ts):
    from datetime import datetime, timezone
    ts = ts.rstrip('Z').split('.')[0] + '+00:00'
    return int(datetime.fromisoformat(ts).timestamp())

seen = set()
total = 0.0

for root, _dirs, files in os.walk(projects_dir):
    for fname in files:
        if not fname.endswith('.jsonl'):
            continue
        try:
            with open(os.path.join(root, fname), encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                    except Exception:
                        continue
                    if data.get('type') != 'assistant':
                        continue
                    msg = data.get('message') or {}
                    if not isinstance(msg, dict):
                        continue
                    try:
                        if parse_epoch(data.get('timestamp', '1970-01-01T00:00:00Z')) < window_start:
                            continue
                    except Exception:
                        continue
                    msg_id = msg.get('id', '')
                    if msg_id and msg_id in seen:
                        continue
                    if msg_id:
                        seen.add(msg_id)
                    usage = msg.get('usage') or {}
                    if not usage:
                        continue
                    tier = get_tier(msg.get('model', ''))
                    p = PRICING[tier]
                    inp = usage.get('input_tokens',                0)
                    out = usage.get('output_tokens',               0)
                    cc  = usage.get('cache_creation_input_tokens', 0)
                    cr  = usage.get('cache_read_input_tokens',     0)
                    total += (inp/1e6)*p['i'] + (out/1e6)*p['o'] + (cc/1e6)*p['cc'] + (cr/1e6)*p['cr']
        except Exception:
            pass

print(f'{total:.8f}')
PYEOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local session_key
    session_key=$(get_tmux_option "@claude_usage_session_key" "")

    # Allow tests to force local mode even when a session key is configured
    [[ -n "${CLAUDE_USAGE_TEST_FORCE_LOCAL:-}" ]] && session_key=""
    # Allow tests to inject a fake session key without a real tmux session
    [[ -n "${CLAUDE_USAGE_TEST_SESSION_KEY:-}" ]] && session_key="${CLAUDE_USAGE_TEST_SESSION_KEY}"

    # Try API first when session key is configured
    if [[ -n "$session_key" ]]; then
        if _fetch_from_api "$session_key"; then
            _emit
            return 0
        fi
        # API failed - note error but fall through to local
        local api_error="$CLAUDE_ERROR"
        # Reset defaults for local pass
        CLAUDE_SOURCE="local"; CLAUDE_APPROX=1
        CLAUDE_5H_PCT=-1; CLAUDE_5H_RESET=""
        CLAUDE_7D_PCT=-1; CLAUDE_7D_RESET=""
        CLAUDE_7D_OPUS_PCT=-1; CLAUDE_7D_OPUS_RESET=""
        CLAUDE_7D_SONNET_PCT=-1; CLAUDE_7D_SONNET_RESET=""
        CLAUDE_ERROR="api_fallback:${api_error}"
    fi

    # Local JSONL fallback
    local projects_dir="${CLAUDE_USAGE_TEST_PROJECTS_DIR:-${HOME}/.claude/projects}"
    local plan
    plan=$(get_tmux_option "@claude_usage_plan" "auto")
    [[ "$plan" == "auto" ]] && plan=$(detect_plan)

    local window_start
    window_start=$(hours_ago_epoch 5)

    _fetch_from_local "$projects_dir" "$window_start" "$plan" || true

    _emit
}

main "$@"
