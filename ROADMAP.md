# Venuu — Development Roadmap

> Last updated: March 2026
> Reference: `venuu_deck_v4.pptx` (pitch deck) · `venuu_spec.docx` (technical spec)

This file tracks what is built, what comes next, and the order to build it. Each phase is independently deployable. Tasks are ordered by dependency and business priority.

**Target: App Store launch Q2 2026.** Phases are ordered to get a production-ready, two-sided marketplace live as fast as possible. Infrastructure is built for scale from day one — no retroactive migrations.

---

## Completed (Phases 1–5)

Everything below is built, deployed, and working.

- [x] **Auth & skeleton** — Cognito user pool, Amplify iOS, register/login, API Gateway + Lambda
- [x] **Venue discovery** — MapKit integration, 6 concurrent searches, venue markers with busyness colors, custom map controls (compass, 2D/3D, recenter), Discover tab with category filtering
- [x] **Busyness engine** — Time-based heuristic estimation per venue type, peak hours/days, confidence labels (Estimated / Few reports / Reported)
- [x] **User reports** — POST /reports, report submission UI (1–5 scale + optional wait time), optimistic updates, nearby report fetch, report overlay on map markers
- [x] **Performance** — TaskGroup concurrent search (~400ms), 2-min search cache, parallel report fetch (async let), reactive location (no polling), live 60s refresh, 100-venue cap, chain/POI filtering, deduplication

### Current API Surface

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/reports?lat=&lng=&radius=` | Nearby report summaries |
| POST | `/reports` | Submit busyness report |
| GET | `/venues/{venueId}/reports` | Single venue report history |
| GET | `/user/profile` | User profile & stats |

### Current DynamoDB Tables

| Table | PK | SK | Notes |
|-------|----|----|-------|
| VenueReports | venueId | timestamp | TTL: 2 hours |
| UserProfiles | userId | — | Atomic report counter |

---

## Phase 6 — Owner Ecosystem (Posting + Onboarding + Claiming)

**Goal:** Enable the two-sided marketplace end-to-end — owners can apply, get verified, claim their venue, and post live wait status. This is the product differentiator and the foundation for revenue.

**Priority:** HIGHEST — nothing else matters until this works.

**Why merged:** Owner posting (old Phase 6) requires owners to exist, which requires onboarding (old Phase 8). Shipping them separately creates a broken state. Build the full owner pipeline in one phase.

### Backend

- [ ] Migrate to single-table DynamoDB schema (`venuu-main`) with PK/SK composite keys
  - Entity patterns: `USER#<id>/PROFILE`, `RESTAURANT#<id>/PROFILE`, `RESTAURANT#<id>/STATUS#CURRENT`, etc.
  - Add GSI1 (ByStatus), GSI2 (ByOwner), GSI3 (ByGeohash — geohash5, ~5km cells)
  - **Geohash is built into the schema from day one** — no future migration needed. Use `ngeohash` to encode lat/lng at precision 5. Lambda post-filters by Haversine.
- [ ] Add `role` field to Cognito custom attributes (`CUSTOMER` | `OWNER` | `ADMIN`)
- [ ] Create `Restaurant` entity in DynamoDB (restaurantId, ownerId, name, address, lat/lng, geohash5, hours, photos, isVerified)
- [ ] `POST /v1/auth/owner-apply` — submit application (venue name, address, Google Maps URL/Place ID, optional verification doc)
- [ ] `POST /v1/auth/owner-approve` — admin approves/rejects (ADMIN role only)
  - On approve: update Cognito role to OWNER, create Restaurant entity, link to user
  - Send SES email notification to applicant
- [ ] S3 upload flow for verification documents
  - Lambda generates presigned PUT URL
  - Client uploads directly to `venuu-media/applications/<appId>/verification.pdf`
  - Private bucket policy — admin-only access via signed URLs
- [ ] `POST /v1/restaurants/:id/status` — owner posts wait status (waitMinutes, statusLabel, customMessage)
  - Preset labels: NO_WAIT, SHORT, MODERATE, LONG, FULLY_BOOKED, CLOSED
  - Auto-expires after 90 minutes (TTL), shown as "Possibly outdated" to users
  - Auth: OWNER role + must own the restaurant
- [ ] `GET /v1/restaurants/:id/status` — current status + recent history
- [ ] `DELETE /v1/restaurants/:id/status` — clear current status
- [ ] Write migration Lambda to copy existing VenueReports/UserProfiles into `venuu-main` single-table format
- [ ] Keep old tables active during migration; cut over when verified

### iOS App

- [ ] "Claim your venue" flow accessible from profile or venue detail sheet
  - Step 1: Search/select venue (MapKit search or manual entry)
  - Step 2: Enter business details (name, address, Google URL)
  - Step 3: Optional document upload (utility bill / business license)
  - Step 4: Confirmation screen ("We'll review within 24–48 hours")
- [ ] Add owner tab (visible only when user role = OWNER)
  - Current posted status display
  - One-tap preset buttons: "No wait" · "15 min" · "30 min" · "45 min" · "60+ min" · "Fully booked"
  - Custom message input field
  - Incoming user reports feed
  - Staleness indicator (badge when status >90 min old)
- [ ] Update venue detail sheet to show owner-posted status when available
  - Display: "Owner posted X min ago" with timestamp
  - Differentiate owner status vs. user-reported data visually
- [ ] Update `BusynessEngine` to incorporate owner status as highest-priority signal
  - Owner fresh (<90 min): show owner wait, HIGH confidence
  - Owner stale + user reports: show user average, MEDIUM confidence
  - No owner + reports: current behavior
  - No data: heuristic only, ESTIMATED confidence
- [ ] Push notification on owner application approval/rejection (APNs via SNS)
- [ ] Profile screen: show "Owner" badge and linked venue when verified

---

## Phase 7 — Launch Hardening & App Store Submission

**Goal:** Production-harden the app and infrastructure. Ship to the App Store. Seed the pilot district. The app must feel polished, trustworthy, and complete on day one.

**Depends on:** Phase 6 (owner ecosystem must be live for the two-sided launch)

### Infrastructure

- [ ] AWS WAF on API Gateway (rate limiting, bot protection)
- [ ] CloudWatch alarms: Lambda errors, DynamoDB throttling, API 5xx rate
- [ ] CloudFront CDN for S3 assets
- [ ] GPS verification for user reports (launch-critical anti-cheat)
  - Reject reports from accounts >200m from venue
  - Weight by proximity: 1.0 (<50m), 0.8 (<100m), 0.5 (<200m)
- [ ] New account throttling: reports from accounts <7 days old weighted at 20%
- [ ] Push notification infrastructure (APNs via SNS) for owner alerts and user engagement

### iOS App

- [ ] App Store metadata, screenshots, description
- [ ] Privacy policy and terms of service screens
- [ ] Onboarding tutorial (first-launch walkthrough)
- [ ] Favorites / saved venues — bookmark venues for quick access, show on Discover tab
- [ ] Deep links (open venue detail from shared URL)
- [ ] Haptic polish pass across all interactions
- [ ] Accessibility audit (VoiceOver, Dynamic Type)
- [ ] Analytics integration (track key events: search, report submit, venue tap, owner status post)
- [ ] New account onboarding: explain that report influence grows with account age

### Launch Strategy (from pitch deck)

- [ ] Seed one dense walkable district (20–30 restaurants)
- [ ] Contact owners personally, offer 6 months free Pro
- [ ] Partner with local food bloggers + neighbourhood groups
- [ ] Target: 15 posting owners, 200 DAU in pilot zone
- [ ] Geo-targeted social: "Know before you go in [City]"

---

## Phase 8 — Trust Engine & Conflict Detection

**Goal:** Merge owner and user data intelligently. Surface conflicts transparently. Build user trust in the displayed wait time.

**Depends on:** Phase 6 (owner posting must exist)

### Backend

- [ ] Implement server-side `TrustEngine` Lambda (or layer)
  - Input: owner status + recent user reports (last 45 min) + historical average
  - Per-report trust weight: `accountAgeFactor × proximityFactor × historyFactor`
    - Account age: 0.2 (<7d), 0.6 (<30d), 1.0 (30d+)
    - Proximity: 1.0 (<50m), 0.8 (<100m), 0.5 (<200m), reject (>200m)
    - History: user's reliabilityScore / 100 (min 0.3)
  - Merge logic: weighted average of owner status (70% base) and user reports
  - Conflict detection: |ownerWait - userAvg| > 15 min AND 3+ reports → flag conflict
- [ ] `GET /v1/restaurants/:id` — returns merged trust output (displayedWait, confidence, source, conflictDetected, ownerWait, userReportedWait)
- [ ] `GET /v1/restaurants/nearby?lat=&lng=&radius=` — list venues with computed wait (public endpoint)

### iOS App

- [ ] Update venue detail sheet for trust engine output
  - Show confidence source badge: "Owner verified" / "User reported" / "Estimated"
  - On conflict: show both numbers — "Owner: 15 min · Users reporting: ~40 min"
  - Color-code confidence: green (high) → yellow (medium) → gray (estimated)
- [ ] Update map markers to reflect trust-engine confidence visually

---

## Phase 9 — Revenue & Monetization

**Goal:** Activate the two launch-ready revenue streams from the pitch deck. Start generating MRR.

**Depends on:** Phase 6 (owner accounts)

### Owner SaaS Subscriptions

- [ ] Pricing tiers in backend (Free / Basic $29 / Pro $59 / Multi $99)
  - Free: basic status posting, 5 user reports/day, Venuu listing badge
  - Basic: unlimited updates, full report feed, custom messages, priority support
  - Pro: promoted placement slot, busy-hour analytics, monthly reliability report
  - Multi: up to 5 locations, group analytics, API access, SLA support
- [ ] Stripe integration for subscription billing
- [ ] Tier-gated features in Lambda (check subscription level on each request)
- [ ] Free 30-day trial → auto-convert to Free tier if not upgraded
- [ ] In-app subscription management (upgrade/downgrade/cancel)

### Promoted Placement

- [ ] `POST /v1/restaurants/:id/promote` — activate promoted placement
- [ ] Promoted venues appear at top of nearby results when wait is genuinely low
  - Ethical constraint: only show promoted badge when current wait < 15 min
- [ ] Billing: CPM or flat weekly rate per zone
- [ ] "Promoted" label visible to users (transparency)

### Data API (Year 2)

- [ ] Aggregated, anonymized wait-time trends API
- [ ] Tiered access: $500–$5k/mo
- [ ] Target customers: hospitality platforms, booking apps, city planners

---

## Phase 10 — Reliability Scoring & Anti-Cheat

**Goal:** Reward accurate owners. Penalize gaming. Build the data moat that makes Venuu impossible to replicate.

**Depends on:** Phase 8 (trust engine)

### Backend

- [ ] `POST /v1/reports/:id/upvote` — upvote a report as accurate
- [ ] `POST /v1/reports/:id/dispute` — flag a report as inaccurate
- [ ] EventBridge nightly job (3am): calculate reliability scores
  - Per venue: `(confirmedPosts / (confirmed + disputed)) × 100`
  - Band: HIGH (≥80), MEDIUM (≥50), LOW (<50)
  - Store in `RESTAURANT#<id>/RELIABILITY#<weekYear>`
- [ ] Reliability badge shown on venue (high-trust venues get "Venuu Verified" badge)
- [ ] SNS push to owner on conflict detection (3+ reports disagree with posted status)

### iOS App

- [ ] Show reliability badge on venue detail sheet and markers
- [ ] Report upvote/dispute buttons on venue detail sheet

---

## Phase 11 — Web Dashboard (Owner Host Stand)

**Goal:** Tablet-friendly web app for the host stand. Owners update wait status without pulling out their phone. Real-time feed of user reports.

**Depends on:** Phase 6 (owner posting), Phase 9 (subscription tiers gate dashboard access)

**Timeline:** Q3 2026 per pitch deck milestones.

### Infrastructure

- [ ] React app hosted on AWS Amplify
- [ ] Cognito auth (same user pool as iOS)
- [ ] API Gateway WebSocket endpoint for real-time updates
  - `$connect` / `$disconnect` — owner connection management (store in DynamoDB: `CONNECTION#<connId>/OWNER#<ownerId>`)
  - `reportReceived` — push new user report to connected owner
  - `disputeAlert` — push when conflict threshold reached

### Dashboard Features

- [ ] Large status display (readable from 3+ feet away)
- [ ] One-click update buttons matching mobile presets
- [ ] Live feed of incoming user reports (WebSocket)
- [ ] Dispute banner: "X users are reporting a longer wait than you posted"
- [ ] Weekly reliability score display
- [ ] Venue profile editor: hours, cuisine, photos, description

---

## Future Considerations (Post-Launch)

These are not committed phases — evaluate after launch data comes in.

- **Push notifications for users** — "Your saved venue just posted 'No wait'"
- **Wait time notifications** — "Alert me when wait drops below 15 min"
- **Social features** — "X friends are at this venue" (requires opt-in location sharing)
- **Owner referral program** — refer an owner → 2 months free (from GTM strategy)
- **Venuu Verified SEO badge** — owners add badge to Google listing for inbound discovery
- **Second city expansion** — replicate pilot playbook; target 230+ paying owners for break-even
- **Android app** — evaluate after iOS proves PMF
- **Search improvements** — full-text venue search, cuisine filters, "open now" filter
- **Historical trends** — "This venue is usually busy at this time" with chart
- **Multi-language support** — for expansion beyond English-speaking markets
- **Photo upload for venues** — presigned S3 PUT → `venuu-media/restaurants/<id>/photos/`
- **ElastiCache (Redis)** — computed wait time caching (60s TTL), evaluate if needed at scale
