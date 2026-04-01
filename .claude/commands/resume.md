# Resume from Saved Session

Resume work from a previously saved session file.

## Instructions

### 1. Find Session File
If the user provided a path: $ARGUMENTS — read that file.
If no path provided: list files in `.claude/sessions/` and read the most recent one.

### 2. Load Context
Read the session file thoroughly. Pay special attention to:
- **What Did NOT Work** — do NOT retry these approaches
- **Current State** — verify it matches (check branch, run git status)
- **Key Decisions** — carry these forward
- **Exact Next Step** — this is where you start

### 3. Verify State
- Confirm you're on the correct branch
- Check if the build still passes
- Note any new changes since the session was saved

### 4. Start Working
State: "Resuming from [session description]. Starting with: [exact next step]"
Then begin the next step immediately.
