#!/usr/bin/env bats
# test_fetch.bats - tests for fetch_usage.sh (local JSONL mode)

load test_helpers.bash

FETCH="${REPO_DIR}/scripts/fetch_usage.sh"

setup() {
    setup_test_dir
    # Force local mode even if a real session key is configured in tmux
    export CLAUDE_USAGE_TEST_FORCE_LOCAL=1
}

teardown() {
    unset CLAUDE_USAGE_TEST_FORCE_LOCAL
    teardown_test_dir
}

# ---------------------------------------------------------------------------
# Helpers: run fetch and parse output into variables
# ---------------------------------------------------------------------------
run_fetch() {
    run bash "$FETCH"
}

parse_pct() {
    echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2
}

parse_approx() {
    echo "$output" | grep '^CLAUDE_APPROX=' | cut -d= -f2
}

parse_source() {
    echo "$output" | grep '^CLAUDE_SOURCE=' | cut -d= -f2
}

parse_error() {
    echo "$output" | grep '^CLAUDE_ERROR=' | cut -d= -f2
}

# ---------------------------------------------------------------------------
# No data cases
# ---------------------------------------------------------------------------

@test "empty projects dir → PCT=0, APPROX=1, SOURCE=local" {
    run_fetch
    [ "$status" -eq 0 ]
    [ "$(parse_pct)"    = "0" ]
    [ "$(parse_approx)" = "1" ]
    [ "$(parse_source)" = "local" ]
}

@test "projects dir has JSONL but all messages older than 5h → PCT=0" {
    local f="${TEST_PROJECTS_DIR}/test-project/old.jsonl"
    write_jsonl_message "$f" "claude-sonnet-4-6" 100000 10000 0 0 10
    run_fetch
    [ "$status" -eq 0 ]
    [ "$(parse_pct)" = "0" ]
}

# ---------------------------------------------------------------------------
# Basic percentage calculation
# ---------------------------------------------------------------------------

@test "sonnet messages in window → non-zero PCT" {
    local f="${TEST_PROJECTS_DIR}/test-project/session.jsonl"
    # ~$3.6 cost → 20% of Pro $18 limit
    # Sonnet output: $15/1M → need $3.6 → 240k output tokens
    # Let's use 1M input ($3) + 40k output ($0.6) = $3.6 exactly
    write_jsonl_message "$f" "claude-sonnet-4-6" 1000000 40000 0 0 1
    run_fetch
    [ "$status" -eq 0 ]
    local pct
    pct=$(parse_pct)
    [ "$pct" -gt 0 ]
    [ "$pct" -le 100 ]
}

@test "PCT is approximate (APPROX=1) for local source" {
    local f="${TEST_PROJECTS_DIR}/test-project/session.jsonl"
    write_jsonl_message "$f" "claude-sonnet-4-6" 100000 1000 0 0 1
    run_fetch
    [ "$status" -eq 0 ]
    [ "$(parse_approx)" = "1" ]
    [ "$(parse_source)"  = "local" ]
}

@test "opus messages cost more than sonnet for same token count → higher PCT" {
    local f_opus="${TEST_PROJECTS_DIR}/test-project/opus.jsonl"
    local f_son="${TEST_PROJECTS_DIR}/test-project/sonnet.jsonl"

    write_jsonl_message "$f_opus" "claude-opus-4-6"   100000 10000 0 0 1
    OPUS_DIR="$(mktemp -d)"
    mkdir -p "${OPUS_DIR}/projects/p"
    cp "$f_opus" "${OPUS_DIR}/projects/p/opus.jsonl"

    write_jsonl_message "$f_son" "claude-sonnet-4-6" 100000 10000 0 0 1
    SON_DIR="$(mktemp -d)"
    mkdir -p "${SON_DIR}/projects/p"
    cp "$f_son" "${SON_DIR}/projects/p/sonnet.jsonl"

    CLAUDE_USAGE_TEST_PROJECTS_DIR="${OPUS_DIR}/projects" run bash "$FETCH"
    local opus_pct
    opus_pct=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    CLAUDE_USAGE_TEST_PROJECTS_DIR="${SON_DIR}/projects" run bash "$FETCH"
    local son_pct
    son_pct=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    [ "$opus_pct" -gt "$son_pct" ]

    rm -rf "$OPUS_DIR" "$SON_DIR"
}

@test "PCT never exceeds 100" {
    local f="${TEST_PROJECTS_DIR}/test-project/heavy.jsonl"
    # Massively over the limit
    write_jsonl_message "$f" "claude-opus-4-6" 10000000 10000000 0 0 1
    run_fetch
    [ "$status" -eq 0 ]
    [ "$(parse_pct)" -le 100 ]
}

# ---------------------------------------------------------------------------
# Cache tokens (cache_creation, cache_read) contribute to cost
# ---------------------------------------------------------------------------

@test "cache_creation tokens increase cost" {
    local f_nocache="${TEST_PROJECTS_DIR}/test-project/nocache.jsonl"
    local f_cache="${TEST_PROJECTS_DIR}/test-project/cache.jsonl"

    write_jsonl_message "$f_nocache" "claude-sonnet-4-6" 100000 0 0       0 1
    NOCACHE_DIR="$(mktemp -d)"; mkdir -p "${NOCACHE_DIR}/projects/p"
    cp "$f_nocache" "${NOCACHE_DIR}/projects/p/"

    write_jsonl_message "$f_cache" "claude-sonnet-4-6"   100000 0 100000 0 1
    CACHE_DIR_T="$(mktemp -d)"; mkdir -p "${CACHE_DIR_T}/projects/p"
    cp "$f_cache" "${CACHE_DIR_T}/projects/p/"

    CLAUDE_USAGE_TEST_PROJECTS_DIR="${NOCACHE_DIR}/projects" run bash "$FETCH"
    local pct_no
    pct_no=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    CLAUDE_USAGE_TEST_PROJECTS_DIR="${CACHE_DIR_T}/projects" run bash "$FETCH"
    local pct_cc
    pct_cc=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    [ "$pct_cc" -gt "$pct_no" ]

    rm -rf "$NOCACHE_DIR" "$CACHE_DIR_T"
}

# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------

@test "duplicate message IDs are counted only once" {
    local f="${TEST_PROJECTS_DIR}/test-project/dupes.jsonl"
    # Write the same message ID twice
    local ts
    if [[ "$(uname)" == "Darwin" ]]; then
        ts=$(date -u -v-1H '+%Y-%m-%dT%H:%M:%S.000Z')
    else
        ts=$(date -u -d "1 hour ago" '+%Y-%m-%dT%H:%M:%S.000Z')
    fi

    for i in 1 2; do
        echo '{"type":"assistant","message":{"id":"msg_FIXED_ID","model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"'"$ts"'"}' >> "$f"
    done

    local f_single="${TEST_PROJECTS_DIR}/test-project/single.jsonl"
    echo '{"type":"assistant","message":{"id":"msg_FIXED_ID","model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"'"$ts"'"}' >> "$f_single"

    # PCT with dupes should equal PCT with single
    CLAUDE_USAGE_TEST_PROJECTS_DIR="${TEST_PROJECTS_DIR}" run bash "$FETCH"
    local pct_dupes
    pct_dupes=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    DUPE_DIR="$(mktemp -d)"; mkdir -p "${DUPE_DIR}/projects/p"
    cp "$f_single" "${DUPE_DIR}/projects/p/"
    CLAUDE_USAGE_TEST_PROJECTS_DIR="${DUPE_DIR}/projects" run bash "$FETCH"
    local pct_single
    pct_single=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    [ "$pct_dupes" = "$pct_single" ]

    rm -rf "$DUPE_DIR"
}

# ---------------------------------------------------------------------------
# Multiple projects
# ---------------------------------------------------------------------------

@test "messages across multiple project directories are summed" {
    mkdir -p "${TEST_PROJECTS_DIR}/proj-a" "${TEST_PROJECTS_DIR}/proj-b"
    write_jsonl_message "${TEST_PROJECTS_DIR}/proj-a/s.jsonl" "claude-sonnet-4-6" 500000 0 0 0 1
    write_jsonl_message "${TEST_PROJECTS_DIR}/proj-b/s.jsonl" "claude-sonnet-4-6" 500000 0 0 0 1

    local fa="${TEST_PROJECTS_DIR}/proj-a"
    local fb="${TEST_PROJECTS_DIR}/proj-b"

    # Single project PCT
    CLAUDE_USAGE_TEST_PROJECTS_DIR="$fa" run bash "$FETCH"
    local pct_a
    pct_a=$(echo "$output" | grep '^CLAUDE_PCT=' | cut -d= -f2)

    # Both projects PCT
    run_fetch
    local pct_both
    pct_both=$(parse_pct)

    # pct_both should be roughly 2× pct_a (allow integer rounding)
    [ "$pct_both" -gt "$pct_a" ]
}
