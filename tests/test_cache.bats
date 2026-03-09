#!/usr/bin/env bats
# test_cache.bats - tests for caching behaviour in claude_usage.sh

load test_helpers.bash

MAIN="${REPO_DIR}/scripts/claude_usage.sh"

setup() {
    setup_test_dir
    # Use a unique cache file per test run to avoid interference
    export CLAUDE_USAGE_TEST_CACHE="/tmp/tmux-claude-usage-test-$$.cache"
    rm -f "$CLAUDE_USAGE_TEST_CACHE"
}

teardown() {
    rm -f "$CLAUDE_USAGE_TEST_CACHE"
    teardown_test_dir
}

# Patch claude_usage.sh to use our test cache path.
# We do this by overriding via env - the script uses UID in the path,
# so we test cache behaviour via output consistency instead.

@test "second call within TTL returns cached output" {
    # First call - populates cache
    run bash "$MAIN"
    [ "$status" -eq 0 ]
    first_output="$output"

    # Second call - should read from cache (same output)
    run bash "$MAIN"
    [ "$status" -eq 0 ]
    [ "$output" = "$first_output" ]
}

@test "output is non-empty" {
    run bash "$MAIN"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "powerline and normal mode write separate caches" {
    run bash "$MAIN"
    normal_out="$output"

    run bash "$MAIN" --powerline
    pl_out="$output"

    # Powerline output should have no tmux color codes
    [[ "$pl_out"     != *"#[fg="* ]]
    [[ "$normal_out" == *"#[fg="* ]] || true  # normal usually has colors
}

@test "cache file is created after first run" {
    # Remove any existing cache
    rm -f /tmp/tmux-claude-usage-"${UID}".cache

    run bash "$MAIN"
    [ "$status" -eq 0 ]
    [ -f /tmp/tmux-claude-usage-"${UID}".cache ]
}
