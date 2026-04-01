# De-Sloppify: Cleanup Pass

Review and clean up recently written or modified code. This is a focused cleanup pass — do NOT add new features or refactor beyond what's needed.

## Wayt-Specific Cleanup Awareness
- Don't remove `@MainActor` annotations — they prevent concurrency warnings
- Don't inline FusionService/VenueSearchService cache logic — caching is intentional
- Don't simplify the progressive refresh pattern (+2s, +5s, +12s) — it's designed for Phase B latency
- Don't remove `carryOverExistingBusyness` calls — they prevent grey marker flash
- Keep BusynessEngine score thresholds as-is unless explicitly asked to change them

## Instructions

### 1. Identify Recent Changes
Run `git diff` to see all current modifications.

### 2. Remove Slop
For each modified file, check and fix:

**Remove unnecessary additions:**
- Comments that restate what the code does (keep only "why" comments)
- Docstrings on private/internal methods with self-explanatory names
- Type annotations where Swift inference is unambiguous
- Unused imports or variables
- Empty else blocks or unnecessary else-after-return
- `print()` / `debugPrint()` / `NSLog` statements added during development

**Simplify over-engineering:**
- Abstractions used only once — inline them
- Generic helpers for one-time operations — use direct code
- Unnecessary protocol conformances or extensions
- Feature flags or configuration for things that won't change
- Error handling for impossible internal states (validate at boundaries only: API responses, user input)

**Fix consistency:**
- Match existing patterns: `guard let` for early exits, `async/await` for concurrency
- Use same naming as rest of codebase (check surrounding files)
- Venue busyness fields: `busynessScore`, `busynessLevel`, `busynessConfidence` — match these exactly
- Service method naming: `fetch*` for network, `get*` for cached/computed, `search*` for MapKit

### 3. Do NOT
- Add new features
- Refactor code that wasn't part of the current changes
- Add tests (that's a separate step)
- Change behavior of any function
- Touch BusynessEngine thresholds or fusion weights
- Remove caching logic

### 4. Report
List each cleanup action taken: `[file:line] removed/simplified: description`
End with total count of cleanups.
