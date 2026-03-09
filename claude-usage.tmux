#!/usr/bin/env bash
# claude-usage.tmux - TPM entry point.
#
# Executed once by TPM (or `run-shell`) when the plugin loads.
# Replaces every occurrence of #{claude_usage} in status-left and status-right
# with a #(...) dynamic command that tmux re-evaluates every status-interval.

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${CURRENT_DIR}/scripts/claude_usage.sh"

# Make scripts executable (idempotent)
chmod +x "${SCRIPT}" \
         "${CURRENT_DIR}/scripts/fetch_usage.sh" \
         "${CURRENT_DIR}/scripts/format.sh" \
         "${CURRENT_DIR}/scripts/helpers.sh" \
         "${CURRENT_DIR}/segments/claude_usage.sh" 2>/dev/null || true

PLACEHOLDER='#{claude_usage}'
REPLACEMENT="#(${SCRIPT})"

for option in status-right status-left; do
    value="$(tmux show-option -gqv "$option" 2>/dev/null)"
    if [[ "$value" == *"$PLACEHOLDER"* ]]; then
        new_value="${value//$PLACEHOLDER/$REPLACEMENT}"
        tmux set-option -gq "$option" "$new_value"
    fi
done
