---
paths:
  - "**/*"
---

# Development Workflow Rules — Wayt

## Before Writing Code
- Read existing code in the area you're modifying
- Understand the current pattern before changing it
- For non-trivial features, use `/plan` first

## During Implementation
- Make the smallest change that works
- Test incrementally — don't write 500 lines then hope it compiles
- Keep commits focused — one logical change per commit
- If an approach isn't working after 2-3 attempts, stop and reconsider

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
