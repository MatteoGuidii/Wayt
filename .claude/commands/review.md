# Code Review Current Changes

Review all uncommitted changes as a senior iOS engineer familiar with the Wayt codebase.

## Wayt-Specific Review Context
- `MapViewModel` is the single source of truth for venues — no other VM should fetch independently
- `DiscoverViewModel` derives from MapViewModel via `.onChange(of: mapViewModel.venues)` — never duplicates data
- `VenueFilterState` is shared via @EnvironmentObject — filter logic must use `filterState.apply(to:)`
- Busyness pipeline: FusionService → BusynessEngine.computeLevel() → BusynessLevel (1-5) → marker colors
- FusionService caches for 5 min + 500m movement invalidation — don't break this
- MapKit rate limit: 45 req/60s in VenueSearchService — don't bypass the rate limiter
- Backend fusion weights: user_reports 0.75, foursquare 0.25 — changes here affect all users

## Instructions

### 1. Gather Changes
Run `git diff` and `git diff --cached` to see all modifications.

### 2. Review Each File For

**Correctness**
- Logic errors, off-by-one, race conditions
- Missing error handling at service boundaries (API calls, MapKit queries)
- Incorrect async/await usage or missing @MainActor on UI-updating code
- Score/level math errors in BusynessEngine (0.0-1.0 scores → 1-5 levels)

**Architecture (Wayt MVVM)**
- Business logic leaking into Views (belongs in ViewModels)
- ViewModels calling APIs directly (belongs in Services)
- Any ViewModel fetching venue data independently instead of deriving from MapViewModel
- State management: wrong property wrapper, missing @Published, broken observation chain
- Filter state duplicated instead of using shared VenueFilterState

**Performance (Non-Negotiable for Wayt)**
- Main thread blocking (network/IO in View body, synchronous MapKit calls)
- Excessive SwiftUI re-renders (large @Published objects, unnecessary @State)
- Missing cache usage where FusionService/VenueSearchService cache exists
- Redundant API calls (check if data is already in fusion cache or search cache)
- Phase B dispatches without progressive refresh pattern (+2s, +5s, +12s)

**API Cost**
- New Foursquare/Google calls without caching (these cost real money)
- MapKit queries bypassing VenueSearchService rate limiter
- DynamoDB operations without appropriate TTL

**Security**
- Hardcoded API keys, tokens, or secrets (must be in .env)
- Logging sensitive user data (Cognito tokens, location history)
- Unvalidated backend inputs in Lambda handlers

### 3. Output Format

For each issue found:
```
[SEVERITY] file:line — description
  Suggestion: how to fix
```

Severities: CRITICAL (must fix), WARNING (should fix), NITPICK (optional)

End with: "X critical, Y warnings, Z nitpicks. [Ready / Not ready] to commit."
