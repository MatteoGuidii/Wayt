---
paths:
  - "**/*"
---

# Development Workflow Rules — Wayt

## Before Writing Code
- Read existing code in the area you're modifying
- Understand the current pattern before changing it
- For non-trivial features, use `/plan` first

## Plan Before Execute
- Complex changes must be broken into deliberate phases — never jump straight into a large implementation
- For non-trivial features, create a phased plan:
  - **Phase 1 — Minimum viable:** smallest slice that provides value and compiles
  - **Phase 2 — Core experience:** complete the happy path
  - **Phase 3 — Edge cases:** error handling, edge cases, polish
  - **Phase 4 — Optimization:** performance, monitoring, cleanup
- Each phase must be independently compilable and testable — avoid plans that require all phases to complete before anything works
- Red flags in a plan: phases that can't be delivered independently, steps that aren't verifiable, changes spanning too many files at once

## During Implementation
- **Think incrementally** — each step should be verifiable before moving to the next
- Make the smallest change that works
- Test incrementally — don't write 500 lines then hope it compiles
- Keep commits focused — one logical change per commit
- If an approach isn't working after 2-3 attempts, stop and reconsider

## Verification Checkpoints
- After completing each function or component, verify it builds (`xcodebuild` or Xcode)
- Before moving to the next task, confirm the current one works
- Run verification after every major change — don't batch verification to the end
- If a step breaks the build, fix it before proceeding — never stack changes on a broken foundation

## API Cost Awareness
- Foursquare: raw data cached 30 days, computed scores 10 min — don't bust caches unnecessarily
- Google Places: Enterprise tier for hours — minimize calls, cache aggressively
- MapKit: rate limited to 45 req/60s — always respect the rate limiter
- When changing backend signal code, consider cache invalidation impact

## Backend Changes (Lambda/TypeScript)
- Always run `npx tsc --noEmit` after TypeScript changes
- Test DynamoDB operations with correct key schemas
- Remember TTL fields are Unix timestamps in seconds
- SAM template changes require `sam build && sam deploy`

## iOS Build
- Target: iOS 17+
- Simulator: platform=iOS Simulator,name=iPhone 17 Pro
- Zero warnings policy — fix warnings, don't suppress them
