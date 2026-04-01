# Save Session State

Save the current session state to a file so it can be resumed in a future conversation.

## Instructions

Create a session save file at `.claude/sessions/session-YYYY-MM-DD-HHMM.md` with the following structure. Be thorough and specific — this is the only context the next session will have.

```markdown
# Session: [Date and brief description]

## What We Built
- [Bullet list of completed features/changes with specific file paths]

## What WORKED
- [Approaches and decisions that succeeded, with evidence]
- [Include specific patterns, configurations, or techniques that were effective]

## What Did NOT Work (CRITICAL)
- [Failed approaches with WHY they failed]
- [Error messages, root causes, dead ends]
- [This prevents future sessions from retrying the same failures]

## Current State
- Branch: [branch name]
- Uncommitted changes: [list modified files]
- Build status: [passing/failing + any errors]
- Test status: [passing/failing]

## Key Decisions Made
- [Architecture decisions and their rationale]
- [Tradeoffs that were considered]

## Blockers / Open Questions
- [Anything unresolved]
- [Questions for the user]

## Exact Next Step
- [The very next thing to do — specific enough to start immediately]
- [Include file paths, function names, what to implement]
```

After writing the file, tell the user: "Session saved to [path]. Start your next conversation with: 'Resume from .claude/sessions/[filename]'"
