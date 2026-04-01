# Verify Build, Lint, and Tests

Run a full verification pass on the Wayt codebase. Report results in a structured format.

## Instructions

Run ALL checks — do NOT stop at the first failure. Report complete status.

### 1. Swift Build Check
Run: `xcodebuild build -scheme Wayt -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -20`
Record: PASS or FAIL (with error summary)

### 2. TypeScript Backend Check
Run from `backend/lambda`:
- `npx tsc --noEmit` (type checking)
Record: PASS or FAIL (with error count)

### 3. Secret Scan
Search modified files (from `git diff --name-only`) for:
- Foursquare API keys (`fsq_`, `FOURSQUARE`)
- Google API keys (`AIza`, `GOOGLE_PLACES`)
- AWS credentials (`AKIA`, `aws_secret`)
- Generic patterns: `sk-`, `api_key =`, `password =`, `Bearer `, hardcoded tokens
- Cognito pool IDs or client IDs in source code (should be in config/env only)
Skip: `.env` files, `template.yaml` parameter references, `AppConstants.swift` non-secret constants
Record: PASS or list findings

### 4. Architecture Quick Check
Verify no common Wayt anti-patterns in changed files:
- DiscoverViewModel fetching venues directly (should derive from MapViewModel)
- Views making direct API calls (should go through ViewModels)
- New DynamoDB operations missing TTL fields
- MapKit searches bypassing VenueSearchService

### 5. Git Status
- Uncommitted changes count
- Untracked files that might need staging

## Report Format

```
=== WAYT VERIFICATION REPORT ===

Swift Build:      [PASS/FAIL]
TS Type Check:    [PASS/FAIL]
Secret Scan:      [PASS/FAIL]
Architecture:     [PASS/FAIL]
Git Status:       [clean/X uncommitted changes]

Overall:          [READY / NOT READY] for commit
```

If NOT READY, list specific issues to fix.
