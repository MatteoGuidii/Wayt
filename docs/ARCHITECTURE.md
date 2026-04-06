# Wayt Architecture Guide — Map & Discover

> Detailed reference for new developers. Covers data flow, component relationships, and critical implementation details.
> Last updated: April 6, 2026. Scope: Map and Discover features. Profile, Auth, Settings, and Backend signal processing are documented in `CLAUDE.md`.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [App Entry Point & Navigation](#2-app-entry-point--navigation)
3. [Map Feature — Deep Dive](#3-map-feature--deep-dive)
4. [Discover Feature — Deep Dive](#4-discover-feature--deep-dive)
5. [Shared Services & Data Flow](#5-shared-services--data-flow)
6. [Critical: Do Not Modify](#6-critical-do-not-modify)
7. [Improvement Opportunities](#7-improvement-opportunities)
8. [Key Constants Reference](#8-key-constants-reference)

---

## 1. High-Level Architecture

**Platform:** Native iOS (Swift / SwiftUI)
**Architecture:** MVVM with Environment injection
**Backend:** AWS API Gateway → Lambda (ca-central-1)
**Auth:** AWS Cognito via Amplify
**Map:** Apple MapKit (SwiftUI `Map` view)

### System Overview Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Wayt iOS App                               │
│                                                                     │
│  ┌──────────┐     ┌──────────────┐     ┌───────────────┐           │
│  │  MapKit   │     │ LocationSvc  │     │   AuthState    │          │
│  │ (Apple)   │     │ (CoreLoc.)   │     │  (Cognito)     │          │
│  └────┬──────┘     └──────┬───────┘     └───────┬────────┘          │
│       │                   │                     │                   │
│       ▼                   ▼                     ▼                   │
│  ┌─────────────────────────────────────────────────────────┐       │
│  │              MainTabView (State Owner)                   │       │
│  │  @StateObject: MapViewModel, FilterState,                │       │
│  │                ProfileVM, SavedVenuesVM, TabSelection    │       │
│  └──────┬──────────────┬───────────────────┬───────────────┘       │
│         │              │                   │                        │
│    ┌────▼────┐    ┌────▼─────┐     ┌──────▼───────┐               │
│    │   Map   │    │ Discover │     │   Profile     │               │
│    │  Screen │    │  Screen  │     │   Screen      │               │
│    └────┬────┘    └────┬─────┘     └──────────────┘               │
│         │              │                                           │
│         │    shared venues via                                      │
│         │    @EnvironmentObject                                     │
│         ▼              ▼                                           │
│  ┌──────────────────────────────────────┐                          │
│  │         Backend Services             │                          │
│  │  FusionService ←→ APIClient ←→ AWS  │                          │
│  │  ReportService     (JWT auth)        │                          │
│  │  SavedVenuesService                  │                          │
│  │  LeaderboardService                  │                          │
│  └──────────────────────────────────────┘                          │
└─────────────────────────────────────────────────────────────────────┘
```

### Environment Object Injection Flow

```
WaytApp
  └─ AuthRootView
       ├─ (not signed in) → AuthGateSheet / OnboardingView
       └─ (signed in or guest) → MainTabView
            │
            │  Creates all @StateObject instances:
            │    - TabSelection
            │    - VenueFilterState     ← shared between Map + Discover
            │    - MapViewModel         ← shared between Map + Discover
            │    - ProfileViewModel
            │    - SavedVenuesViewModel
            │
            │  Injects via .environmentObject():
            │
            ├─ MapScreen
            │    reads: MapViewModel, LocationService, AuthState,
            │           VenueFilterState, SavedVenuesViewModel
            │
            ├─ DiscoverScreen
            │    reads: MapViewModel (for venues), LocationService,
            │           AuthState, VenueFilterState, SavedVenuesViewModel,
            │           TabSelection
            │    owns:  @StateObject DiscoverViewModel (local only)
            │
            └─ ProfileScreen
                 reads: ProfileViewModel, AuthState, SavedVenuesViewModel
```

---

## 2. App Entry Point & Navigation

### File: `Wayt/App/WaytApp.swift`
Entry point. Sets up Amplify, creates `AuthState` and `LocationService`.

### File: `Wayt/Views/MainTabView.swift`
The **single source of truth** for all shared state. Three tabs:

| Tab | View | Tag |
|-----|------|-----|
| Map | `MapScreen()` | `.map` |
| Discover | `DiscoverScreen()` | `.discover` |
| Profile | `ProfileScreen()` | `.profile` |

### Tab Switching Flow

```
┌─────────────────────────────────────────────────┐
│  User taps "See on Map" in Discover detail      │
│                                                  │
│  1. mapViewModel.insertVenueIfMissing(venue)    │
│  2. tabSelection.selectedTab = .map              │
│  3. mapViewModel.selectVenue(venue)              │
│  4. Camera animates to venue                     │
│  5. VenueDetailSheet opens on Map tab            │
└─────────────────────────────────────────────────┘
```

### Auth-Protected Actions Flow

```
User taps "Save" or "Report" while not signed in
         │
         ▼
authState.pendingVenue = venue
authState.pendingVenueTab = .discover (or .map)
authState.onRequestSignIn?()          ── presents AuthGateSheet
         │
         ▼
User signs in → authState.venueRestoreToken changes
         │
         ▼
.onChange(of: authState.venueRestoreToken) fires
         │
         ▼
Restores: tabSelection.selectedTab + selectedVenue = pendingVenue
         │
         ▼
VenueDetailSheet re-appears with user now authenticated
```

---

## 3. Map Feature — Deep Dive

### Key Files

| File | Role |
|------|------|
| `Views/Map/MapScreen.swift` | SwiftUI view with `Map()`, overlays, controls |
| `ViewModels/MapViewModel.swift` | Search orchestration, clustering, busyness, state |
| `Views/Map/VenueMarker.swift` | Individual venue pin (icon + name + badges) |
| `Views/Map/ClusterMarkerView.swift` | Cluster circle with count |
| `Services/VenueSearchService.swift` | MapKit search wrapper, caching, rate-limiting |
| `Services/VenueClusterer.swift` | Grid-based O(n) clustering algorithm |
| `Services/FusionService.swift` | Backend busyness estimates (Signal Fusion Engine) |
| `Engine/BusynessEngine.swift` | Score→Level conversion, confidence mapping |
| `Services/VenueFilterState.swift` | Shared category + busyness filter |

### Map Search Pipeline — Complete Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                    searchVenues(in: region)                           │
│                    MapViewModel.swift:140                             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Cancel previous searchTask, expandTask, followUpTask             │
│  2. Reset rate limiter (user-initiated)                              │
│  3. Debounce 300ms (skipped on first launch)                         │
│                                                                      │
│  ┌─── PHASE A (concurrent) ──────────────────────────────────────┐  │
│  │                                                                │  │
│  │  ┌──────────────────────┐   ┌─────────────────────────────┐   │  │
│  │  │  Area Pre-fetch      │   │  MapKit Multi-Search         │   │  │
│  │  │  FusionService       │   │  VenueSearchService          │   │  │
│  │  │  .prefetchArea()     │   │  .searchAllTypes()           │   │  │
│  │  │                      │   │                               │   │  │
│  │  │  POST /v1/venues/    │   │  Batch 1 (concurrent):       │   │  │
│  │  │    nearby            │   │    restaurant, cafe,          │   │  │
│  │  │  (no venue list      │   │    nightlife, bakery,         │   │  │
│  │  │   = cached only)     │   │    brewery, winery            │   │  │
│  │  │                      │   │                               │   │  │
│  │  │  Populates           │   │  Batch 2 (concurrent):       │   │  │
│  │  │  fusion cache        │   │    bar, lounge, brunch,       │   │  │
│  │  │       │              │   │    pub, diner, restaurant     │   │  │
│  │  │       ▼              │   │                               │   │  │
│  │  │  Apply cached ──────►│   │  Each batch triggers          │   │  │
│  │  │  estimates to        │   │  onBatch callback:            │   │  │
│  │  │  early batches       │   │    - Merge new venues         │   │  │
│  │  └──────────────────────┘   │    - Apply busyness data      │   │  │
│  │                             │    - Recompute clusters        │   │  │
│  │                             │      (debounced 100ms)         │   │  │
│  │                             │    - Stop spinner on 1st batch │   │  │
│  │                             └─────────────────────────────────┘   │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─── Busyness Application (single pass) ────────────────────────┐  │
│  │  Priority 1: Carry over existing busyness (prevents grey flash)│  │
│  │  Priority 2: Cached fusion estimates from FusionService        │  │
│  │  Priority 3: Offline fallback (neutral / no confidence)        │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─── PHASE B (background, non-blocking) ────────────────────────┐  │
│  │                                                                │  │
│  │  Identify uncached venues (confidence == .none)                │  │
│  │         │                                                      │  │
│  │         ▼                                                      │  │
│  │  POST /v1/venues/nearby  ← with venue list                    │  │
│  │  (backend returns instantly, computes async)                   │  │
│  │         │                                                      │  │
│  │         ▼                                                      │  │
│  │  Schedule progressive follow-up refreshes:                     │  │
│  │    +3s  → overlay busyness data                                │  │
│  │    +7s  → overlay busyness data                                │  │
│  │    +14s → overlay busyness data (final)                        │  │
│  │                                                                │  │
│  │  Each refresh: re-fetches from fusion cache, applies to        │  │
│  │  venues, recomputes clusters. Cancels early if all venues      │  │
│  │  have real data.                                               │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─── Final Merge ───────────────────────────────────────────────┐  │
│  │  - Keep existing in-region venues (containsWithBuffer 10%)     │  │
│  │  - Add new results not already present                         │  │
│  │  - Sort by distance from region center                         │  │
│  │  - Cap at maxVisibleVenues (300)                               │  │
│  │  - Schedule hours transition refresh                           │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### Clustering Algorithm

**File:** `Services/VenueClusterer.swift`

```
Input: [Venue] + MKCoordinateRegion (visible area)
Algorithm: Grid-based, O(n)

┌─────────────────────────────────────────┐
│  Map visible region                      │
│                                          │
│  Divided into 8×8 grid cells            │
│  ┌───┬───┬───┬───┬───┬───┬───┬───┐     │
│  │   │ • │   │   │   │   │   │   │     │
│  ├───┼───┼───┼───┼───┼───┼───┼───┤     │
│  │   │•• │   │   │ • │   │   │   │     │  •• = 2+ venues in cell
│  ├───┼───┼───┼───┼───┼───┼───┼───┤     │       → becomes CLUSTER
│  │   │   │   │•••│   │   │   │   │     │
│  ├───┼───┼───┼───┼───┼───┼───┼───┤     │  •  = 1 venue in cell
│  │   │   │ • │   │   │   │   │   │     │       → stays SINGLE
│  └───┴───┴───┴───┴───┴───┴───┴───┘     │
│                                          │
│  Clustering DISABLED when:               │
│    span < 0.005° (~500m) = zoomed in     │
│                                          │
│  Cluster position = centroid of venues   │
│  Cluster color = avg busyness of         │
│    open venues with confidence data      │
└─────────────────────────────────────────┘

Output: [VenueMapItem]
  - .single(Venue)
  - .cluster(VenueCluster)
```

**Recompute triggers:**
- Region change (pan/zoom) via `onMapCameraChange`
- Filter change via Combine observer on `VenueFilterState`
- Venue data update (busyness overlay, new search results)
- Debounced (100ms) during progressive loading to prevent flicker

### Map Interactions

```
┌────────────────────────────────────────────────────────────┐
│  TAP ON VENUE PIN                                          │
│  ────────────────                                          │
│  1. viewModel.selectVenue(venue, heading, pitch)           │
│  2. Camera animates to venue at 800m distance              │
│     (preserves current heading + pitch)                    │
│  3. .sheet(item: selectedVenue) presents VenueDetailSheet  │
│  4. Pin scales up 1.12x with animation                     │
│  5. Pin gets highest zIndex (100) to draw on top           │
├────────────────────────────────────────────────────────────┤
│  TAP ON CLUSTER                                            │
│  ──────────────                                            │
│  1. Zoom into cluster region (span / 3)                    │
│  2. Spring animation (response: 0.4, damping: 0.85)        │
│  3. At new zoom level, cluster may split into singles      │
├────────────────────────────────────────────────────────────┤
│  PAN / ZOOM                                                │
│  ──────────                                                │
│  1. onMapCameraChange(frequency: .onEnd) fires             │
│  2. viewModel.onRegionChanged(newRegion) called            │
│  3. Updates currentRegion for clustering                   │
│  4. Shows "Search This Area" if:                           │
│     - Moved > 0.005° from last search center, OR           │
│     - Zoomed > 1.5x from last search span                  │
│  5. Pre-fetches fusion data for new area (background)      │
│  6. Recomputes clusters for new zoom level                 │
├────────────────────────────────────────────────────────────┤
│  "SEARCH THIS AREA" BUTTON                                 │
│  ─────────────────────────                                 │
│  1. Resets MapKit rate limiter                              │
│  2. Calls searchVenues(in: visibleRegion)                  │
│  3. Full search pipeline restarts                          │
├────────────────────────────────────────────────────────────┤
│  RECENTER BUTTON                                           │
│  ───────────────                                           │
│  Returns to .userLocation(fallback:) with animation        │
├────────────────────────────────────────────────────────────┤
│  3D TOGGLE                                                 │
│  ─────────                                                 │
│  Switches pitch between 0° and 45°                         │
│  Map style elevation: .realistic ↔ .flat                   │
├────────────────────────────────────────────────────────────┤
│  COMPASS                                                   │
│  ───────                                                   │
│  Visible when heading ≠ 0. Tap resets heading to north.    │
└────────────────────────────────────────────────────────────┘
```

### Venue Pin Anatomy

```
         ┌──────┐ ← Wait time badge (top-right)
         │ 5min │   or Saved badge (top-left, orange)
         └──────┘

      ┌──────────────┐
      │   ┌──────┐   │ ← 40×40pt circle
      │   │  🍕  │   │   Category icon
      │   └──────┘   │   Colored by busyness level:
      │              │     Green (Empty) → Red (Packed)
      └──────┬───────┘
             │         ← Anchor triangle
             ▼
      ─────────────
       Venue Name      ← Text label below pin
      ─────────────

  Confidence ring:
    - Dashed → Estimated (low confidence)
    - Solid thin → Medium confidence
    - Solid thick → High/Very High confidence

  Selected state:
    - Scale 1.12x
    - zIndex 100 (on top of everything)
```

### MapKit Rate Limiting & Caching

```
┌─────────────────────────────────────────────────────────────┐
│  MapKit Rate Limit Strategy                                  │
│  ─────────────────────────                                   │
│                                                              │
│  Apple limit: 50 requests / 60 seconds (all MapKit calls)   │
│  Internal MapKit (annotation renders, etc): ~15 requests     │
│  Our budget: 35 requests / 60 seconds                        │
│                                                              │
│  Sliding window: track timestamps, prune expired ones        │
│  On rate limit hit: serve stale cache (better than nothing)  │
│  On "Search This Area": reset window (explicit user action)  │
│                                                              │
│  Search Cache:                                               │
│  ─────────────                                               │
│  Key: normalized query + bucketed region (~100m precision)    │
│  TTL: 5 minutes                                              │
│  Max entries: 50 (LRU eviction)                              │
│  Stale fallback: serve expired cache on rate-limit hit       │
└─────────────────────────────────────────────────────────────┘
```

### Live Refresh System

```
┌──────────────────────────────────────────────────────────────┐
│  startLiveRefresh()  — called from MainTabView.task          │
│                                                              │
│  Every 120 seconds (when app is active):                     │
│    1. overlayBusynessData()                                  │
│       - Re-fetches from FusionService cache                  │
│       - Applies updated levels/confidence to venues          │
│       - Recomputes clusters                                  │
│                                                              │
│  Hours Transition Refresh:                                   │
│    - Parses hoursToday ("Opens 11:00 AM", "Closes 10 PM")   │
│    - Schedules one-shot refresh at next transition + 5s      │
│    - On fire: invalidates fusion cache, re-overlays          │
│    - Ensures "Open Now" status is accurate                   │
│                                                              │
│  Cancelled on:                                               │
│    - Tab disappear                                           │
│    - App background                                          │
│    - ViewModel deinit                                        │
└──────────────────────────────────────────────────────────────┘
```

### Expand Search (Pagination)

```
User taps "See more venues" in Discover
            │
            ▼
  mapViewModel.expandSearch()
            │
            ▼
  ┌─────────────────────────────────────────┐
  │  Expand region by AppConstants          │
  │  .expandIncrement (1000m) beyond        │
  │  lastExpandedRegion (or lastSearched)   │
  │                                         │
  │  Cap at maxWalkingRadius (5000m)        │
  │                                         │
  │  Invalidate VenueSearchService cache    │
  │  (region grew, old keys stale)          │
  │                                         │
  │  searchAllTypes(region: expanded)       │
  │     - Merge new results with existing   │
  │     - Deduplicate by venue ID           │
  │     - Apply busyness data               │
  │     - Recompute clusters                │
  │                                         │
  │  If count < 300 && radius < 5km:        │
  │    "See more venues" stays enabled      │
  │  Else:                                  │
  │    "Showing all walkable venues"         │
  └─────────────────────────────────────────┘
```

---

## 4. Discover Feature — Deep Dive

### Key Files

| File | Role |
|------|------|
| `Views/Discover/DiscoverScreen.swift` | UI layout, sections, filter chips, carousels |
| `ViewModels/DiscoverViewModel.swift` | Filter pipeline, derived collections, stats |
| `Services/VenueFilterState.swift` | Shared filter (also used by Map) |

### Screen Layout

```
┌─────────────────────────────────────────┐
│  Good morning! ☀️                        │  ← Time-based greeting
│  Find a cozy coffee spot                │     + contextual subtitle
├─────────────────────────────────────────┤
│  ▏ Vibe Pulse                           │
│  ┌──┐ ┌──┐ ┌────┐ ┌──┐ ┌──┐           │  ← Tappable bar chart
│  │  │ │  │ │    │ │  │ │  │           │     busyness distribution
│  │  │ │  │ │    │ │  │ │  │           │     of ALL nearby venues
│  │12│ │25│ │ 40 │ │18│ │ 5│           │
│  └──┘ └──┘ └────┘ └──┘ └──┘           │     Tap bar → filter by
│  Empty Quiet Mod  Busy Packed           │     that busyness level
├─────────────────────────────────────────┤
│  [🍽 Restaurants 45] [🍺 Bars 23]       │  ← Category filter pills
│  [🌙 Clubs 8] [☕ Cafés 31]             │     with venue counts
├─────────────────────────────────────────┤
│  [Open Now] [3.5+] [4+] [4.5+]         │  ← Discover-only filters
│  [$] [$$] [$$$+]                        │     (not shared with Map)
├─────────────────────────────────────────┤
│  ▸ Saved Places (3 nearby)              │  ← Collapsible, only if
│    • Café Roma  ☕  Quiet                │     signed in + has nearby
│    • The Pub    🍺  Busy                 │     saved venues
├─────────────────────────────────────────┤
│  🟢 Go Now — Sweet spots                │  ← Busyness 1-3
│  ┌────────┐ ┌────────┐ ┌────────┐      │     Horizontal carousel
│  │ Café A │ │ Diner B│ │ Bar C  │ ···  │     Up to 8 venues
│  │ ☕ 4.2 │ │ 🍽 4.5 │ │ 🍺 3.8│      │
│  │ Quiet  │ │ Empty  │ │ Mod.   │      │
│  └────────┘ └────────┘ └────────┘      │
├─────────────────────────────────────────┤
│  🔥 On Fire — Buzzing right now         │  ← Busyness 4-5
│  ┌────────┐ ┌────────┐ ┌────────┐      │     Horizontal carousel
│  │ Club X │ │ Bar Y  │ │ Rest Z │ ···  │     Up to 10 venues
│  │ 🌙 4.7 │ │ 🍺 4.1 │ │ 🍽 4.3│      │     Sorted by busyness desc
│  │ Packed │ │ Busy   │ │ Busy   │      │
│  └────────┘ └────────┘ └────────┘      │
├─────────────────────────────────────────┤
│  All Spots                              │  ← Full filtered list
│  ┌─────────────────────────────────┐    │     VenueRow cards
│  │ 📍 Café Roma                    │    │     Sorted by distance
│  │    Coffee · Open · Closes 10 PM │    │     (or rating if filter)
│  │    ⬤ Quiet  ★ 4.2  $$          │    │
│  └─────────────────────────────────┘    │
│  ┌─────────────────────────────────┐    │
│  │ 📍 The Burger Joint             │    │
│  │    Restaurant · Open · Closes…  │    │
│  │    ⬤ Moderate  ★ 4.5  $$       │    │
│  └─────────────────────────────────┘    │
│  ...                                    │
│  ┌─────────────────────────────────┐    │
│  │  See more venues                │    │  ← Triggers expandSearch()
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

### Discover Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  MapViewModel.venues  ──────────────►  DiscoverScreen            │
│  (source of truth)         │           .onChange(of: venues)     │
│                            │                    │                │
│                            │                    ▼                │
│                            │           DiscoverViewModel         │
│                            │           .updateVenues()           │
│                            │                    │                │
│                            │          ┌─────────┴─────────┐     │
│                            │          │                    │     │
│                            │          ▼                    ▼     │
│                            │   Sort by distance     Skip sort   │
│                            │   (if location moved    (if same    │
│                            │    > 50m OR venue       venue set   │
│                            │    set changed)         + location) │
│                            │          │                    │     │
│                            │          └─────────┬──────────┘     │
│                            │                    │                │
│                            │                    ▼                │
│                            │           applyFilter()             │
│                            │                    │                │
│                            │    ┌───────────────┼────────────┐  │
│                            │    │               │            │  │
│                            │    ▼               ▼            ▼  │
│                            │  recompute     Shared        Discover│
│                            │  DerivedState  Filters       Filters│
│                            │    │           (category     (open  │
│                            │    │            busyness)     now,  │
│                            │    │               │          rating│
│                            │    │               │          price)│
│                            │    │               │            │  │
│                            │    │               └──────┬─────┘  │
│                            │    │                      │        │
│                            │    ▼                      ▼        │
│                            │  vibePulse         base (filtered) │
│                            │  categoryCounts          │         │
│                            │                    ┌─────┼─────┐   │
│                            │                    │     │     │   │
│                            │                    ▼     ▼     ▼   │
│                            │              popular  sweet  filtered│
│                            │              Venues   Spot   Venues │
│                            │              (4-5)    (1-3)  (all) │
│                            │              max 10   max 8        │
└──────────────────────────────────────────────────────────────────┘
```

### Filter Pipeline Detail

```
applyFilter() — DiscoverViewModel.swift:202

  Input: venues (distance-sorted)
         │
         ├─ 1. VenueFilterState.apply()
         │     ├─ selectedCategory? → filter by category match
         │     └─ selectedBusynessLevel? → filter by level match
         │
         ├─ 2. openNowOnly? → filter venue.isOpen == true
         │
         ├─ 3. ratingFilter? → filter venue.rating >= threshold
         │     (3.5, 4.0, or 4.5)
         │
         └─ 4. priceFilter? → filter by price bucket
               ├─ $ → FREE or INEXPENSIVE
               ├─ $$ → MODERATE
               └─ $$$+ → EXPENSIVE or VERY_EXPENSIVE

  Output splits:
    ├─ popularVenues: base + busyness ≥ 4, sorted desc, max 10
    ├─ sweetSpotVenues: base + busyness 1-3, max 8
    └─ filteredVenues: base (sorted by rating if ratingFilter active)
```

### Section Visibility Rules

```
Saved Places:   shown if authState.isSignedIn
                AND nearbySavedVenues is not empty

Go Now:         shown if sweetSpotVenues is not empty
                AND showGoNow (no active busyness filter ≥ 4)

On Fire:        shown if popularVenues is not empty
                AND showOnFire (no active busyness filter ≤ 3)

All Spots:      always shown (may be empty state)
```

### Derived Statistics

| Property | Source | Purpose |
|----------|--------|---------|
| `vibePulse` | ALL venues (unfiltered) | Area mood bar chart |
| `categoryCounts` | Venues filtered by busyness only | Category pill counts |
| `areaMood` | Average of all venue busyness levels | Greeting context |
| `greeting` | Current hour | "Good morning/evening/..." |
| `greetingSubtitle` | Current hour | "Find a cozy coffee spot" etc. |

---

## 5. Shared Services & Data Flow

### APIClient (Actor)

**File:** `Services/APIClient.swift`

```
┌──────────────────────────────────────────────────────────┐
│  APIClient (actor — thread-safe singleton)                │
│                                                           │
│  Base URL: AWS API Gateway (ca-central-1)                 │
│                                                           │
│  Auth: AWS Cognito ID token (JWT)                         │
│    - Cached with expiry tracking                          │
│    - Refreshes 60s before expiry                          │
│    - Automatically attached to every request              │
│                                                           │
│  Retry: Transient 5xx errors                              │
│    - Max 2 retries                                        │
│    - Exponential backoff: 200ms, 400ms                    │
│                                                           │
│  Methods:                                                 │
│    get<T: Decodable>(path:) → T                           │
│    post<Body: Encodable, T: Decodable>(path:body:) → T   │
│    put<Body: Encodable, T: Decodable>(path:body:) → T    │
│    delete(path:)                                          │
│    uploadImage(presignedURL:imageData:)                   │
└──────────────────────────────────────────────────────────┘
```

### FusionService — Busyness Data Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│  FusionService.shared                                            │
│                                                                  │
│  Cache: [venueId: FusedEstimateResponse]                         │
│    Max 500 entries (LRU eviction)                                │
│    TTL: AppConstants.reportCacheTTL (300s / 5 min)               │
│    Invalidated if user moves > 500m                              │
│                                                                  │
│  Endpoints:                                                      │
│                                                                  │
│  1. prefetchArea(lat, lng, radius)                               │
│     POST /v1/venues/nearby (empty venue list)                    │
│     → Returns all cached estimates in area                       │
│     → Populates local cache for instant hits                     │
│                                                                  │
│  2. fetchNearbyEstimates(lat, lng, radius, venues)               │
│     POST /v1/venues/nearby (with venue list)                     │
│     → Returns cached + dispatches uncached for async compute     │
│     → Backend computes using Google Popular Times, user reports  │
│                                                                  │
│  3. fetchVenueBusyness(venueId, name, lat, lng)                  │
│     GET /v1/venues/{id}/busyness                                 │
│     → Full details for single venue (detail sheet)               │
│                                                                  │
│  Response shape (FusedEstimateResponse):                         │
│    busynessScore: Double (0.0 – 1.0)                             │
│    confidence: String (NONE/LOW/MEDIUM/HIGH/VERY_HIGH/ESTIMATED) │
│    reportCount: Int                                              │
│    waitMinutes: Int?                                             │
│    isOpen: Bool?                                                 │
│    hoursToday: String?                                           │
│    businessStatus: String?                                       │
│    venueDetails: { rating, userRatingCount, priceLevel, ... }    │
└──────────────────────────────────────────────────────────────────┘
```

### BusynessEngine — Score Conversion

```
BusynessEngine.estimate(from: FusedEstimateResponse)
    │
    ├─ Score 0.0–0.2 → .empty    (level 1, green)
    ├─ Score 0.2–0.4 → .quiet    (level 2, yellow-green)
    ├─ Score 0.4–0.6 → .moderate (level 3, yellow)
    ├─ Score 0.6–0.8 → .busy     (level 4, orange)
    └─ Score 0.8–1.0 → .packed   (level 5, red)

    Confidence mapping:
    ├─ "NONE"      → .none       (grey, no data)
    ├─ "ESTIMATED" → .estimated  (dashed ring)
    ├─ "LOW"       → .low
    ├─ "MEDIUM"    → .medium
    ├─ "HIGH"      → .high       (solid ring)
    └─ "VERY_HIGH" → .veryHigh   (thick solid ring)
```

### VenueFilterState (Shared)

```
┌──────────────────────────────────────────────────────────┐
│  VenueFilterState (@MainActor, ObservableObject)          │
│                                                           │
│  @Published selectedCategory: VenueCategory?              │
│  @Published selectedBusynessLevel: BusynessLevel?         │
│                                                           │
│  Behavior: Toggle (select again to deselect)              │
│                                                           │
│  Observers:                                               │
│    MapViewModel → recomputeClusters()                     │
│    DiscoverViewModel → applyFilter()                      │
│                                                           │
│  Both tabs react simultaneously to any filter change      │
└──────────────────────────────────────────────────────────┘
```

### Venue ID Generation

```
venue.id = normalized_name + "_" + lat(5 decimals) + "_" + lng(5 decimals)

Example: "the-coffee-shop_43.65107_-79.34729"

  - Normalized: lowercase, trimmed, diacritics removed
  - 5 decimal places ≈ 1.1m precision
  - Prevents duplicates across different MapKit search queries
  - Same physical venue from "café" and "coffee" searches → same ID
```

### Cross-Tab Communication Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   MapScreen                        DiscoverScreen                │
│   ─────────                        ───────────────               │
│       │                                  │                       │
│       │  MapViewModel.venues ───────────►│ .onChange → update    │
│       │  (source of truth)               │                       │
│       │                                  │                       │
│       │◄── VenueFilterState ────────────►│                       │
│       │    (bidirectional)               │                       │
│       │                                  │                       │
│       │◄── "See on Map" ────────────────►│                       │
│       │    (tab switch + venue select)   │                       │
│       │                                  │                       │
│       │  expandSearch() ◄────────────────│ "See more venues"    │
│       │  (called from Discover)          │                       │
│       │                                  │                       │
│       │  refreshAfterReport() ◄──────────│ (detail sheet dismiss)│
│       │                                  │                       │
│       │──── NotificationCenter ─────────►│                       │
│       │     .reportSubmitted             │ (triggers refresh)    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Critical: Do Not Modify

These areas have subtle, load-bearing logic. Changing them without full understanding risks breaking core functionality:

### 1. Venue ID Generation (`Models/Venue.swift`)
- The ID is a normalized key used everywhere: fusion cache, saved venues, deduplication
- Changing the format breaks cache hits, saved venue lookups, and creates duplicates
- The 5-decimal precision is intentional (~1m accuracy)

### 2. MapKit Rate Limiting (`VenueSearchService.swift`)
- The 35-request limit and sliding window prevent Apple from throttling the app
- The 15-request reserve for internal MapKit calls is based on real-world observation
- Removing or relaxing this causes silent search failures

### 3. Phase A/B Search Pipeline (`MapViewModel.searchVenues`)
- The two-phase approach (prefetch → MapKit → background compute) is carefully ordered
- Phase A pre-populates the cache so early batches get colors immediately
- Phase B dispatches uncached venues with progressive follow-ups
- Removing any phase causes either "grey flash" (no colors) or stale data

### 4. Clustering Debounce (`MapViewModel.recomputeClusters`)
- The 100ms debounce during progressive loading prevents O(n) clustering from firing on every batch
- Without it, map stutters as 12 concurrent search batches complete

### 5. Busyness Carry-Over (`applyAllBusynessData`)
- Priority 1 carries over existing busyness data from the previous search
- This prevents pins from flashing grey between searches
- Order matters: carry-over > cached > offline fallback

### 6. FusionService Cache Invalidation
- Invalidates on user movement > 500m, TTL expiry, and explicit `refreshAfterReport()`
- The LRU eviction at 500 entries prevents memory pressure
- Hours transition refresh ensures open/close status is accurate

### 7. Auth Venue Restore Token (`AuthState`)
- The `pendingVenue` + `pendingVenueTab` + `venueRestoreToken` flow allows seamless auth interruption
- Without it, users lose their place when prompted to sign in

### 8. Task Cancellation in `MapViewModel.deinit`
- 7 different async tasks are cancelled: searchTask, refreshTimer, hoursTransitionTask, clusterDebounceTask, expandTask, prefetchTask, followUpTask
- Missing any cancellation causes retain cycles or zombie network calls

---

## 7. Improvement Opportunities

### Architecture
- **DiscoverViewModel duplication**: DiscoverVM re-implements filter logic that partially overlaps with VenueFilterState. Could be consolidated into a single reactive filter pipeline.
- **Environment object count**: 6 environment objects injected from MainTabView. Consider a single `AppState` container or using the newer `@Observable` macro (iOS 17+) to reduce boilerplate.
- **Service singletons**: `FusionService.shared`, `BusynessEngine.shared` make testing harder. Could use dependency injection via environment or protocol-based services.

### Performance
- **Clustering on main thread**: `VenueClusterer.cluster()` runs synchronously on `@MainActor`. For 300 venues it's fast, but could be moved to a background actor for safety.
- **Distance sorting**: `DiscoverViewModel.updateVenues()` sorts all venues by distance on every update. Could use a spatial index (quadtree) for O(log n) nearest-neighbor queries.
- **Progressive loading batches**: Currently 12 MapKit searches in 2 groups. Could be adaptive based on result count (stop early if already have 200+ venues).

### User Experience
- **No pull-to-refresh on Discover**: Users must switch to Map and back, or wait for live refresh
- **No offline mode**: If the device is offline, venues show with no busyness data. Could cache last-known state to UserDefaults.

### Code Quality
- **Magic numbers**: Several hardcoded values in MapViewModel (0.005 threshold, 300ms debounce, 800m camera distance). Could be moved to `AppConstants`.
- **Error handling**: `catch` blocks mostly just log errors. No user-facing error states (e.g., "No internet connection").

---

## 8. Key Constants Reference

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| `maxVisibleVenues` | 300 | AppConstants | Max venues held in memory / on map |
| `defaultSearchRadius` | 800m | AppConstants | Initial search radius |
| `expandIncrement` | 1,000m | AppConstants | Each "See more" expands by this |
| `maxWalkingRadius` | 5,000m | AppConstants | Maximum expand distance |
| `reportCacheTTL` | 300s (5 min) | AppConstants | Fusion cache lifetime |
| `reportCooldown` | 30 min | AppConstants | Per-venue report cooldown |
| `reportProximityRadius` | ~200m | AppConstants | Must be this close to report |
| `liveRefreshInterval` | 120s | MapViewModel | Busyness auto-refresh cycle |
| `mapKitQueryTimeout` | 8s | VenueSearchService | MapKit request timeout |
| `maxRequestsPerWindow` | 35 | VenueSearchService | MapKit rate limit budget |
| `windowDuration` | 60s | VenueSearchService | Rate limit sliding window |
| `maxCacheEntries` | 50 | VenueSearchService | Query cache size |
| `maxFusionCache` | 500 | FusionService | Busyness estimate cache size |
| `clusterGridDensity` | 8 | VenueClusterer | Grid cells per axis |
| `clusterMinSpan` | 0.005° | VenueClusterer | Disable clustering below this |
| `searchThisAreaThreshold` | 0.005° | MapViewModel | Show button after moving this far |
| `progressiveRefreshDelays` | 3s, 7s, 14s | MapViewModel | Background compute follow-ups |
