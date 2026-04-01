#!/bin/bash
# Warns when modifying linter/formatter/build config files
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

PROTECTED_PATTERNS=(
  ".swiftlint.yml"
  ".swiftformat"
  "tsconfig.json"
  ".eslintrc"
  ".prettierrc"
  "samconfig.toml"
  "Package.resolved"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    jq -n --arg file "$FILE_PATH" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: ("Config file modification detected: " + $file + ". Fix the code to match the config, do not weaken the config to match the code.")
      }
    }'
    exit 0
  fi
done

exit 0
