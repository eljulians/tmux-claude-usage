#!/usr/bin/env bats
# test_format.bats - tests for format.sh

load test_helpers.bash

FORMAT="${REPO_DIR}/scripts/format.sh"

# ---------------------------------------------------------------------------
# Gauge bar
# ---------------------------------------------------------------------------

@test "build_gauge 0% produces all empty blocks" {
    source "${REPO_DIR}/scripts/helpers.sh"
    source "${FORMAT}"
    result=$(build_gauge 0 10)
    [ "$result" = "▱▱▱▱▱▱▱▱▱▱" ]
}

@test "build_gauge 100% produces all filled blocks" {
    source "${REPO_DIR}/scripts/helpers.sh"
    source "${FORMAT}"
    result=$(build_gauge 100 10)
    [ "$result" = "▰▰▰▰▰▰▰▰▰▰" ]
}

@test "build_gauge 50% produces half filled" {
    source "${REPO_DIR}/scripts/helpers.sh"
    source "${FORMAT}"
    result=$(build_gauge 50 10)
    [ "$result" = "▰▰▰▰▰▱▱▱▱▱" ]
}

@test "build_gauge width is configurable" {
    source "${REPO_DIR}/scripts/helpers.sh"
    source "${FORMAT}"
    result=$(build_gauge 100 5)
    [ "$result" = "▰▰▰▰▰" ]
}

# ---------------------------------------------------------------------------
# Color thresholds
# ---------------------------------------------------------------------------

@test "30% → normal color (colour82)" {
    run bash "$FORMAT" 30 1
    [[ "$output" == *"colour82"* ]]
}

@test "65% → warn color (colour220)" {
    run bash "$FORMAT" 65 1
    [[ "$output" == *"colour220"* ]]
}

@test "85% → high color (colour208)" {
    run bash "$FORMAT" 85 1
    [[ "$output" == *"colour208"* ]]
}

@test "97% → crit color (colour196)" {
    run bash "$FORMAT" 97 1
    [[ "$output" == *"colour196"* ]]
}

# ---------------------------------------------------------------------------
# Approximate prefix
# ---------------------------------------------------------------------------

@test "approx=1 adds tilde prefix" {
    run bash "$FORMAT" 42 1
    [[ "$output" == *"~42%"* ]]
}

@test "approx=0 has no tilde" {
    run bash "$FORMAT" 42 0
    [[ "$output" != *"~"* ]]
    [[ "$output" == *"42%"* ]]
}

# ---------------------------------------------------------------------------
# No-data case
# ---------------------------------------------------------------------------

@test "PCT=-1 shows -- placeholder" {
    run bash "$FORMAT" -1 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"--"* ]]
}

@test "PCT=-1 uses grey color" {
    run bash "$FORMAT" -1 1
    [[ "$output" == *"colour244"* ]]
}

# ---------------------------------------------------------------------------
# Powerline mode
# ---------------------------------------------------------------------------

@test "--powerline omits tmux color codes" {
    run bash "$FORMAT" 42 1 --powerline
    [ "$status" -eq 0 ]
    [[ "$output" != *"#[fg="* ]]
    [[ "$output" != *"#[default]"* ]]
}

@test "--powerline still contains percentage" {
    run bash "$FORMAT" 42 1 --powerline
    [[ "$output" == *"42%"* ]]
}

# ---------------------------------------------------------------------------
# Output contains expected segments
# ---------------------------------------------------------------------------

@test "output contains icon and label" {
    run bash "$FORMAT" 42 1
    [[ "$output" == *"Claude"* ]]
}

@test "output contains tier label 5h" {
    run bash "$FORMAT" 42 1
    [[ "$output" == *"5h:"* ]]
}

@test "output is a single line" {
    run bash "$FORMAT" 42 1
    [ "$(echo "$output" | wc -l)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Display presets
# ---------------------------------------------------------------------------

@test "compact format shows tier prefix and no gauge bar" {
    CLAUDE_5H_PCT=42 CLAUDE_7D_PCT=10 CLAUDE_APPROX=1 \
        run bash "$FORMAT" --powerline
    [[ "$output" == *"5h:"* ]]
    [[ "$output" != *"▰"* ]]
    [[ "$output" != *"▱"* ]]
}

@test "gauge format shows bar and no tier prefix" {
    run bash -c "
        source '${FORMAT}'
        get_tmux_option() { case \"\$1\" in @claude_usage_format) echo 'gauge';; @claude_usage_tiers) echo '5h';; *) echo \"\${2:-}\";; esac; }
        CLAUDE_5H_PCT=50 CLAUDE_APPROX=1 CLAUDE_7D_PCT=-1 format_output --powerline
    "
    [[ "$output" == *"▰"* ]]
    [[ "$output" != *"5h:"* ]]
}

@test "compact format (default) shows label" {
    run bash -c "
        source '${FORMAT}'
        get_tmux_option() { case \"\$1\" in @claude_usage_format) echo 'compact';; @claude_usage_tiers) echo '5h';; *) echo \"\${2:-}\";; esac; }
        CLAUDE_5H_PCT=42 CLAUDE_APPROX=1 CLAUDE_7D_PCT=-1 format_output --powerline
    "
    [[ "$output" == *"Claude"* ]]
    [[ "$output" == *"5h:"* ]]
}

@test "minimal format hides label and tier prefix" {
    run bash -c "
        source '${FORMAT}'
        get_tmux_option() { case \"\$1\" in @claude_usage_format) echo 'minimal';; @claude_usage_tiers) echo '5h';; *) echo \"\${2:-}\";; esac; }
        CLAUDE_5H_PCT=42 CLAUDE_APPROX=1 CLAUDE_7D_PCT=-1 format_output --powerline
    "
    [[ "$output" != *"Claude"* ]]
    [[ "$output" != *"5h:"* ]]
    [[ "$output" == *"42%"* ]]
}
