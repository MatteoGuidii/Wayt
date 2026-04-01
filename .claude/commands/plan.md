# Plan Feature Implementation

You are a senior iOS architect planning a feature for the Wayt app — a real-time venue discovery iOS app ("Waze for wait times").

## Context: Wayt Architecture
- **Source of truth:** `MapViewModel` owns all venue data. Other VMs derive from it via `.onChange` — never fetch independently.
- **Data flow:** MapKit search → carryOverBusyness → applyCachedEstimates → applyOfflineBusyness → Phase B (backend fusion) → progressive refresh
- **Shared state:** `VenueFilterState` is an @EnvironmentObject shared across Map and Discover tabs
- **Backend:** Lambda (TypeScript) behind API Gateway. DynamoDB for storage. Fusion engine merges Foursquare + user reports.
- **Key services:** `FusionService` (busyness API), `VenueSearchService` (MapKit), `ReportService` (user reports), `BusynessEngine` (score→level conversion)

## Instructions

Given the user's feature description: $ARGUMENTS

### Step 1: Requirements Analysis
- Restate the feature in your own words to confirm understanding
- List explicit requirements
- List implicit requirements (error handling, edge cases, performance)
- Identify which layers are affected:
  - **Models:** `Venue.swift`, `BusynessLevel.swift`, `VenueCategory.swift`, `BusynessReport.swift`
  - **Services:** `FusionService`, `VenueSearchService`, `ReportService`, `APIClient`, `VenueClusterer`
  - **Engine:** `BusynessEngine` (score conversion + offline fallback)
  - **ViewModels:** `MapViewModel` (source of truth), `DiscoverViewModel` (derived), `VenueDetailViewModel`
  - **Views:** `MapScreen`, `DiscoverScreen`, `VenueDetailSheet`, `MainTabView`
  - **Backend:** `fusion.ts`, `foursquare.ts`, `google.ts`, `userReports.ts`, `getNearbyVenues.ts`
  - **Config:** `AppConstants.swift` (TTLs, thresholds), `template.yaml` (SAM infra)

### Step 2: Existing Code Audit
- Search the codebase for related existing code — does something similar already exist?
- Identify files that will need modification vs new files needed
- Check if the feature touches the busyness pipeline (if so, trace: FusionService → BusynessEngine → MapViewModel → marker colors)
- Check if the feature touches DynamoDB (if so, verify key schemas and TTLs in template.yaml)

### Step 3: Risk Assessment
- **API costs:** Will this increase Foursquare calls (cached 30 days)? Google Places calls (Enterprise tier for hours)? MapKit queries (45 req/60s limit)?
- **Performance:** Does this add work to the main thread? Add re-renders to MapScreen? Increase Phase B latency?
- **Data model:** Does this change DynamoDB table schemas? Require new indexes? Affect TTL behavior?
- **Cross-tab sync:** If touching venues or filters, will Map and Discover stay in sync via VenueFilterState?
- **Cache invalidation:** Does this break existing FusionService cache (5-min + 500m movement) or VenueSearchService cache (5-min, 50 entries)?

### Step 4: Implementation Plan
Break into ordered phases following Wayt's architecture:
1. **Models/Types** — Swift structs/enums + TypeScript interfaces
2. **Backend** — Lambda handlers, signal sources, DynamoDB operations
3. **Services** — iOS service layer (API clients, caching, rate limiting)
4. **Engine** — BusynessEngine if score computation changes
5. **ViewModels** — MapViewModel first (source of truth), then derived VMs
6. **Views** — UI changes last, after data layer is solid

For each phase list: specific files, specific changes, dependencies on other phases.

### Step 5: Wait for Approval
Present the plan clearly and **STOP**. Do NOT write any code until the user confirms.

Ask: "Does this plan look good? Should I adjust anything before I start implementing?"
