#!/usr/bin/env bash
# test_helpers.bash - shared setup/teardown utilities for bats tests.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create a temp directory for each test and clean up after.
setup_test_dir() {
    TEST_DIR="$(mktemp -d)"
    TEST_PROJECTS_DIR="${TEST_DIR}/projects"
    TEST_CREDS_FILE="${TEST_DIR}/.credentials.json"
    mkdir -p "${TEST_PROJECTS_DIR}/test-project"
    export CLAUDE_USAGE_TEST_PROJECTS_DIR="$TEST_PROJECTS_DIR"
}

teardown_test_dir() {
    rm -rf "${TEST_DIR:-}"
    unset CLAUDE_USAGE_TEST_PROJECTS_DIR
    unset CLAUDE_USAGE_TEST_NOW
}

# Write a fake credentials file.
# Args: plan (pro|max5|max20)
write_credentials() {
    local plan="${1:-pro}"
    cat > "${TEST_CREDS_FILE}" << EOF
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-test",
    "subscriptionType": "${plan}",
    "rateLimitTier": "default"
  }
}
EOF
}

# Write a JSONL file with assistant messages in/out of the 5-hour window.
# Args: filename model input_tokens output_tokens cache_creation cache_read hours_ago
# hours_ago < 5  → inside window; hours_ago >= 5 → outside window
write_jsonl_message() {
    local file="$1"
    local model="${2:-claude-sonnet-4-6}"
    local inp="${3:-1000}"
    local out="${4:-100}"
    local cc="${5:-0}"
    local cr="${6:-0}"
    local hours_ago="${7:-1}"

    local ts
    if [[ "$(uname)" == "Darwin" ]]; then
        ts=$(date -u -v-"${hours_ago}H" '+%Y-%m-%dT%H:%M:%S.000Z')
    else
        ts=$(date -u -d "${hours_ago} hours ago" '+%Y-%m-%dT%H:%M:%S.000Z')
    fi

    local msg_id="msg_test_$(date +%s%N)_$$"

    cat >> "$file" << EOF
{"type":"assistant","message":{"id":"${msg_id}","model":"${model}","role":"assistant","usage":{"input_tokens":${inp},"output_tokens":${out},"cache_creation_input_tokens":${cc},"cache_read_input_tokens":${cr}}},"timestamp":"${ts}"}
EOF
}

# Convenience: write N identical messages.
write_jsonl_messages() {
    local file="$1"
    local count="$2"
    shift 2
    local i
    for (( i=0; i<count; i++ )); do
        write_jsonl_message "$file" "$@"
        sleep 0.01  # ensure unique timestamps/IDs
    done
}
