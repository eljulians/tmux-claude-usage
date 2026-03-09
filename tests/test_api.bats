#!/usr/bin/env bats
# test_api.bats - tests for fetch_usage.sh API parsing (mocked, no network)

load test_helpers.bash

FETCH="${REPO_DIR}/scripts/fetch_usage.sh"
FIXTURES="${REPO_DIR}/tests/fixtures"

# ---------------------------------------------------------------------------
# Mock curl via PATH: return fixture content based on URL pattern
# ---------------------------------------------------------------------------
setup() {
    setup_test_dir

    # Create a mock curl that serves fixture data
    MOCK_BIN="${TEST_DIR}/bin"
    mkdir -p "$MOCK_BIN"

    # Mock curl: echoes fixture body and appends HTTP 200 on last line
    cat > "${MOCK_BIN}/curl" << 'MOCK'
#!/usr/bin/env bash
# Minimal curl mock for tmux-claude-usage tests.
# Detects URL pattern and serves appropriate fixture.
URL=""
for arg in "$@"; do
    case "$arg" in
        https://*)  URL="$arg" ;;
    esac
done

FIXTURES="${CLAUDE_USAGE_MOCK_FIXTURES}"

case "$URL" in
    */api/organizations)
        echo '[{"uuid":"mock-org-uuid-1234","name":"Test Org","capabilities":["claude_pro"]}]'
        echo "200"
        ;;
    */api/organizations/*/usage)
        cat "${FIXTURES}/${CLAUDE_USAGE_MOCK_RESPONSE:-api_response_normal.json}"
        echo ""
        echo "200"
        ;;
    *)
        echo "{}"
        echo "404"
        ;;
esac
MOCK
    chmod +x "${MOCK_BIN}/curl"
    export PATH="${MOCK_BIN}:${PATH}"
    export CLAUDE_USAGE_MOCK_FIXTURES="${FIXTURES}"
    export CLAUDE_USAGE_TEST_ORG_ID="mock-org-uuid-1234"
}

teardown() {
    teardown_test_dir
}

# Helper: run fetch with a fake session key
run_fetch_api() {
    CLAUDE_USAGE_MOCK_RESPONSE="${1:-api_response_normal.json}" \
        run bash "$FETCH"
    # Inject session key via tmux option mock: set env var instead
    # (tmux isn't running in tests, so get_tmux_option returns default "")
    # We override by re-running with session key in env
}

run_fetch_with_key() {
    local fixture="${1:-api_response_normal.json}"
    # Use export to guarantee vars reach the bash subprocess on all platforms.
    export CLAUDE_USAGE_TEST_SESSION_KEY="test-session-key"
    export CLAUDE_USAGE_MOCK_RESPONSE="$fixture"
    run bash "$FETCH"
}

parse_var() {
    local var="$1"
    echo "$output" | grep "^${var}=" | cut -d= -f2-
}

# ---------------------------------------------------------------------------
# API response parsing
# ---------------------------------------------------------------------------

@test "API normal response: SOURCE=api, APPROX=0" {
    run_fetch_with_key "api_response_normal.json"
    [ "$(parse_var CLAUDE_SOURCE)" = "api" ]
    [ "$(parse_var CLAUDE_APPROX)" = "0" ]
}

@test "API normal response: 5h PCT=42" {
    run_fetch_with_key "api_response_normal.json"
    [ "$(parse_var CLAUDE_5H_PCT)" = "42" ]
}

@test "API normal response: 7d PCT=15" {
    run_fetch_with_key "api_response_normal.json"
    [ "$(parse_var CLAUDE_7D_PCT)" = "15" ]
}

@test "API normal response: 7d sonnet PCT=22" {
    run_fetch_with_key "api_response_normal.json"
    [ "$(parse_var CLAUDE_7D_SONNET_PCT)" = "22" ]
}

@test "API normal response: null tier (opus) → PCT=-1" {
    run_fetch_with_key "api_response_normal.json"
    [ "$(parse_var CLAUDE_7D_OPUS_PCT)" = "-1" ]
}

@test "API normal response: 5h reset epoch is non-empty" {
    run_fetch_with_key "api_response_normal.json"
    local reset
    reset=$(parse_var CLAUDE_5H_RESET)
    [ -n "$reset" ]
    [ "$reset" -gt 0 ]
}

@test "API normal response: ERROR is empty" {
    run_fetch_with_key "api_response_normal.json"
    [ -z "$(parse_var CLAUDE_ERROR)" ]
}

@test "API at-limit response: 5h PCT=99" {
    run_fetch_with_key "api_response_at_limit.json"
    local pct
    pct=$(parse_var CLAUDE_5H_PCT)
    [ "$pct" -ge 99 ]
    [ "$pct" -le 100 ]
}

@test "API: PCT never exceeds 100 even for 99.8 utilization" {
    run_fetch_with_key "api_response_at_limit.json"
    [ "$(parse_var CLAUDE_5H_PCT)" -le 100 ]
}

# ---------------------------------------------------------------------------
# Helpers unit tests
# ---------------------------------------------------------------------------

@test "iso_to_epoch converts ISO 8601 with +00:00 offset" {
    source "${REPO_DIR}/scripts/helpers.sh"
    local epoch
    epoch=$(iso_to_epoch "2026-03-09T14:00:00.000000+00:00")
    [ -n "$epoch" ]
    [ "$epoch" -gt 1700000000 ]
}

@test "iso_to_epoch converts ISO 8601 with Z suffix" {
    source "${REPO_DIR}/scripts/helpers.sh"
    local epoch
    epoch=$(iso_to_epoch "2026-03-09T14:00:00Z")
    [ -n "$epoch" ]
}

@test "format_countdown shows minutes for < 1h" {
    source "${REPO_DIR}/scripts/helpers.sh"
    [ "$(format_countdown 90)"  = "1m"  ]
    [ "$(format_countdown 750)" = "12m" ]
}

@test "format_countdown shows hours+minutes for >= 1h" {
    source "${REPO_DIR}/scripts/helpers.sh"
    [ "$(format_countdown 7380)" = "2h3m" ]
    [ "$(format_countdown 3600)" = "1h"   ]
}

@test "format_countdown shows 'now' for 0 or negative" {
    source "${REPO_DIR}/scripts/helpers.sh"
    [ "$(format_countdown 0)"  = "now" ]
    [ "$(format_countdown -5)" = "now" ]
}
