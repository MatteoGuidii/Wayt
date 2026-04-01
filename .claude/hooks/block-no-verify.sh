#!/bin/bash
# Blocks --no-verify flag on git commits to protect pre-commit hooks
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ "$COMMAND" == *"--no-verify"* ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Blocked: --no-verify is not allowed. Fix the pre-commit hook issue instead of bypassing it."
    }
  }'
  exit 0
fi

exit 0
