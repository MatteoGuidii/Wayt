# Quick Ship: Review + Commit in One Pass

Fast-track for small changes that don't need a full /review cycle. Scans for critical issues only, then commits.

## Instructions

### 1. Quick Scan
Run `git diff` and `git diff --cached`. Check ONLY for:
- Obvious bugs or logic errors
- Hardcoded secrets or API keys
- Force unwraps without guard
- Print/debugPrint statements left in

If any found: report them and STOP. Do not commit.

### 2. Commit
If clean:
- Stage the relevant changed files (not all — be selective)
- Write a concise conventional commit message (feat/fix/refactor/chore)
- Commit

Use the user's description if provided: $ARGUMENTS

### 3. Report
Show the commit hash and one-line summary.
