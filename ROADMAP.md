# Venuu — Development Roadmap

> Last updated: March 2026
> Reference: `venuu_deck_v4.pptx` (pitch deck) · `venuu_spec.docx` (technical spec)

This file tracks what is built, what comes next, and the order to build it. Each phase is independently deployable. Tasks are ordered by dependency and business priority.

**Target: App Store launch Q2 2026.** Phases are ordered to get a production-ready, two-sided marketplace live as fast as possible. Infrastructure is built for scale from day one — no retroactive migrations.

---

## Completed (Phases 1–5)

Everything below is built, deployed, and working.

- [x] **Auth & skeleton** — Cognito user pool, Amplify iOS, register/login, API Gateway + Lambda
- [x] **Venue discovery** — MapKit integration, concurrent searches (~10-12 query terms), venue markers with busyness colors, custom map controls (compass, 2D/3D, recenter), Discover tab with 4 broad category filters (Food, Drinks, Nightlife, Coffee & Tea). Internally stores raw `MKPointOfInterestCategory` from MapKit for accurate classification; computes broad `VenueCategory` for display.
- [x] **Busyness engine** — Report-based estimation with exponential decay weighting, confidence labels (Estimated / Few reports / Reported). Generic time-based heuristic removed — replaced by Foursquare venue-specific historical baseline (Phase 7). Offline fallback uses cached reports or neutral default.
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
- [ ] Create `Restaurant` entity in DynamoDB (restaurantId, ownerId, name, address, lat/lng, geohash5, hours, photos, isVerified, googlePlaceId)
  - Add signal cache entity pattern: `SIGNAL#<venueId>/<sourceId>#<timestamp>` with per-source TTLs
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
- [ ] Refactor `BusynessEngine` for multi-source signal fusion
  - Add `estimate(from: FusedEstimateResponse)` — primary path, consumes server-computed estimates
  - `estimateOffline()` uses cached reports only (no heuristic) — generic heuristic removed, replaced by Foursquare baseline server-side (Phase 7)
  - Owner status becomes one signal among many (weight: 0.90, highest authority)
- [ ] Push notification on owner application approval/rejection (APNs via SNS)
- [ ] Profile screen: show "Owner" badge and linked venue when verified

---

## Phase 7 — Launch Hardening & App Store Submission

**Goal:** Production-harden the app and infrastructure. Ship to the App Store. Seed the pilot district. The app must feel polished, trustworthy, and complete on day one — with multi-source data that users trust immediately.

**Depends on:** Phase 6 (owner ecosystem must be live for the two-sided launch)

### Signal Fusion Engine (launch-critical)

- [ ] Server-side `computeVenueBusyness` Lambda — the Signal Fusion Engine
  - Collects all `VenueSignal` sources, weights by source reliability × freshness decay × confidence
  - Corroboration bonus: 3+ sources agreeing within 0.15 → 1.3× weight boost
  - Conflict detection: max−min > 0.3 among fresh sources → flag and show both sides
  - Confidence levels: VERY_HIGH (3+ agreeing) / HIGH (2+) / MEDIUM (1 direct) / LOW (historical only) / ESTIMATED (Foursquare baseline only)
- [ ] `GET /v1/venues/nearby?lat=&lng=&radius=` — returns venues with fused busyness estimates
- [ ] `GET /v1/venues/{id}/busyness` — single venue detailed estimate with source breakdown
- [ ] Foursquare Places API integration — historical baseline (free tier: 200K calls/mo)
  - Venue matching: MapKit venue name + lat/lng → Foursquare `match` endpoint → `fsq_id` (cached in DynamoDB, 30-day TTL)
  - Fetch venue-specific popularity data: `popularity` (0.0-1.0), `hours_popular`, `stats.total_checkins`
  - **Replaces generic time-based heuristic** — venue-specific historical data instead of fake per-type guesses
  - Base weight: 0.40 (historical baseline). No freshness decay (stable data). Cache with 12h TTL.
- [ ] Google Places Popular Times integration (~$500/mo pilot district)
  - Venue ID mapping pipeline: MapKit venue → Google Place ID (cached in DynamoDB, 30-day TTL)
  - Venue-specific historical busyness curves + live busyness where available
  - Base weight: 0.45 (historical), 0.70 (live busyness where available)
- [ ] Apple WeatherKit integration (free with dev account)
  - One API call per geohash5 region per hour
  - Modifier signal: rain −15%, snow −25%, extreme heat −10%, perfect weather +10%
- [ ] EventBridge rule (every 5 min): refresh expired signals for active areas only
  - Track active areas via `ACTIVE_AREA#<geohash5>` items in DynamoDB
- [ ] Signal cache in DynamoDB with per-source TTLs (Foursquare 12h, Google 24h, weather 60min, owner 90min, reports 2h)

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

## Phase 8 — Event Signals, Trust Refinement & Calibration

**Goal:** Add event-based signals and refine trust scoring. Cross-validation across Foursquare (Phase 7) + Google + owner + user reports already provides strong confidence; this phase adds predictive event signals and makes the fusion engine smarter over time.

**Depends on:** Phase 7 (Signal Fusion Engine + Foursquare baseline must be live)

### Backend

- [ ] Event data integration (Ticketmaster + Eventbrite — free APIs)
  - Fetch events per metro area daily, cache with 6h TTL
  - Modifier signal: major event ending within 30min & 1km of venue → +20% busyness prediction
  - "Raptors game ends at 10pm → nearby bars packed by 10:15" — predictive signal no competitor has
- [ ] Per-report trust weight refinement in fusion engine
  - `accountAgeFactor × proximityFactor × historyFactor` applied to each user report signal
    - Account age: 0.2 (<7d), 0.6 (<30d), 1.0 (30d+)
    - Proximity: 1.0 (<50m), 0.8 (<100m), 0.5 (<200m), reject (>200m)
    - History: user's reliabilityScore / 100 (min 0.3)
- [ ] Venue-specific calibration: learn correction factors over time
  - "Google says 0.7 but users consistently report 0.85 here" → venue-specific adjustment
  - Store in `RESTAURANT#<id>/CALIBRATION` entity
- [ ] Cross-source confidence escalation
  - When Foursquare + Google + user reports agree within 0.15 → VERY_HIGH confidence
  - Source divergence alerts for data quality monitoring

### iOS App

- [ ] Update venue detail sheet for multi-source confidence
  - Show confidence source badge: "Verified" (3+ sources) / "Confirmed" (2+) / "Likely" (1) / "Estimated"
  - On conflict: show both numbers — "Owner: 15 min · Users reporting: ~40 min"
  - Color-code: green (Verified/Confirmed) → yellow (Likely) → gray (Estimated)
- [ ] Update map markers to reflect confidence level visually
- [ ] Source breakdown on venue detail: "Based on: Owner status, 5 user reports, Google data"

---

## Phase 9 — Revenue & Monetization

**Goal:** Activate the two launch-ready revenue streams from the pitch deck. Start generating MRR. POS integration tied to Pro tier creates the ultimate data advantage.

**Depends on:** Phase 6 (owner accounts)

### Owner SaaS Subscriptions

- [ ] Pricing tiers in backend (Free / Basic $29 / Pro $59 / Multi $99)
  - Free: basic status posting, 5 user reports/day, Venuu listing badge
  - Basic: unlimited updates, full report feed, custom messages, priority support
  - Pro: POS integration (automatic status), promoted placement slot, busy-hour analytics, monthly reliability report
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

### POS Integration (Pro Tier Upsell)

- [ ] Square POS integration — OAuth flow, webhook receiver Lambda
  - "Connect your POS and never manually update again" — convenience feature for owners
  - Transaction velocity → busyness signal (weight: 0.85, ground truth)
  - Even 20% of venues with POS connected calibrates the model for ALL venues
- [ ] Toast POS API integration (second POS)
- [ ] "Connect your POS" step in owner settings / profile
- [ ] OpenTable partnership pursuit (BD, not engineering) — reservation data if accessible

### Data API (Year 2)

- [ ] Aggregated, anonymized wait-time trends API — powered by multi-source fused data
- [ ] Tiered access: $500–$5k/mo
- [ ] Target customers: hospitality platforms, booking apps, city planners

---

## Phase 10 — Reliability Scoring & Anti-Cheat

**Goal:** Reward accurate owners. Penalize gaming. Cross-source validation makes reliability scores far more robust than user upvotes alone.

**Depends on:** Phase 8 (cross-validation signals)

### Backend

- [ ] `POST /v1/reports/:id/upvote` — upvote a report as accurate
- [ ] `POST /v1/reports/:id/dispute` — flag a report as inaccurate
- [ ] EventBridge nightly job (3am): calculate reliability scores
  - Cross-source validation: compare owner-posted status against Google + user reports + POS data (if connected)
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

### Data Intelligence
- **ML prediction model** — train on 6+ months of multi-source data to predict busyness 1-2 hours ahead. Use historical patterns + current signals + weather + events as features. The ultimate moat.
- **SafeGraph / Placer.ai** — foot traffic analytics for model calibration ($1K+/mo, evaluate post-revenue)
- **Public transit feeds (GTFS-RT)** — high ridership at nearby station = incoming foot traffic. Cool differentiator, complex to calibrate.
- **Historical trends** — "This venue is usually busy at this time" with chart (partially available from Google Popular Times data already integrated)

### User Features
- **Push notifications for users** — "Your saved venue just posted 'No wait'"
- **Wait time notifications** — "Alert me when wait drops below 15 min"
- **Social features** — "X friends are at this venue" (requires opt-in location sharing)
- **Search improvements** — full-text venue search, cuisine filters, "open now" filter
- **Photo upload for venues** — presigned S3 PUT → `venuu-media/restaurants/<id>/photos/`

### Growth & Expansion
- **Owner referral program** — refer an owner → 2 months free (from GTM strategy)
- **Venuu Verified SEO badge** — owners add badge to Google listing for inbound discovery
- **Second city expansion** — replicate pilot playbook; target 230+ paying owners for break-even
- **Android app** — evaluate after iOS proves PMF
- **Multi-language support** — for expansion beyond English-speaking markets

### Infrastructure
- **ElastiCache (Redis)** — computed wait time caching (60s TTL), evaluate if needed at scale
