#!/bin/bash
# Sends a macOS notification when Claude is waiting for input
osascript -e 'display notification "Task complete — waiting for input" with title "Claude Code" sound name "Glass"' 2>/dev/null
exit 0
