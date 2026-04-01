# Extract and Save a Learned Pattern

Extract a reusable pattern or insight from the current session and save it for future use.

## Instructions

Analyze what was just accomplished in this session and identify the non-obvious insight or pattern.

### What qualifies as worth learning:
- A workaround for a library quirk (MapKit, SwiftUI, DynamoDB, etc.)
- A debugging technique that solved a hard problem
- An API behavior that isn't obvious from docs
- A performance optimization pattern specific to this stack
- A configuration gotcha that took time to figure out

### What does NOT qualify:
- Standard coding patterns (these are in the rules)
- Anything already documented in CLAUDE.md
- Simple bug fixes with obvious causes

### Save Format

Write to the Claude memory system at `~/.claude/projects/-Users-matteo-Desktop-Wayt/memory/` as a memory file:

```markdown
---
name: [descriptive name]
description: [one-line description specific enough to match future searches]
type: feedback
---

[The pattern/insight in 2-4 sentences]

**Why:** [Root cause or reason this matters]
**How to apply:** [When to use this — specific trigger conditions]
```

Update `MEMORY.md` with a pointer to the new file.

Tell the user what was learned and when it will be useful.
