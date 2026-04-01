---
paths:
  - "**/*.swift"
---

# Swift Design Patterns — Wayt

## MVVM Architecture
- **Model:** Pure data types (structs), no UI or networking
- **ViewModel:** @Observable or ObservableObject, owns business logic, calls Services
- **View:** SwiftUI views, observes ViewModel, no direct service calls
- **Service:** Networking, persistence, system APIs — injected into ViewModels

## Dependency Injection
- Use protocol-based DI with default parameters for production instances
- Example: `init(fusionService: FusionServiceProtocol = FusionService.shared)`
- This enables testing with mock implementations without a DI container

## State Management Hierarchy
- `@State` — view-local, simple values
- `@StateObject` — view-owned ObservableObject (created once)
- `@ObservedObject` — passed-in ObservableObject (not owned)
- `@EnvironmentObject` — shared across view tree (like VenueFilterState)

## Caching Pattern
- Cache at the service layer, not in ViewModels
- Use time-based expiry (TTL) appropriate to data freshness needs
- Serve stale cache immediately, refresh in background
- Clear cache on significant context changes (location move, filter change)

## Single Source of Truth
- MapViewModel owns all venue data
- Other ViewModels derive from it via observation — never fetch independently
- Filter state is shared via @EnvironmentObject, never duplicated

## Loading States
Use explicit states for async operations:
```swift
enum LoadState<T> {
    case idle
    case loading
    case loaded(T)
    case failed(Error)
}
```

## Search-First Principle
Before writing new code:
1. Does it already exist in the repo?
2. Is there a Swift/system framework for it?
3. Can an existing service/utility be extended?
4. Only then: write new code
