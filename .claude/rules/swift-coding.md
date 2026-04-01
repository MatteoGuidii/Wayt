---
paths:
  - "**/*.swift"
---

# Swift Coding Standards — Wayt

## Naming
- camelCase for variables, functions, parameters
- PascalCase for types, protocols, enums
- Follow Apple API Design Guidelines: clarity at point of use, no unnecessary words
- Boolean properties read as assertions: `isLoading`, `hasReports`, `canSubmit`

## Immutability & Safety
- Prefer `let` over `var` — use `var` only when mutation is required
- Never force unwrap (`!`) — use `guard let`, `if let`, or nil coalescing
- Use `guard` for early exits, `if let` for optional branching
- Prefer value types (struct/enum) over reference types (class) unless identity semantics needed

## Concurrency (Swift 6+)
- Use `async/await` — never completion handlers for new code
- Mark UI-updating code `@MainActor`
- Use actors for shared mutable state (not locks or DispatchQueue)
- Use `Task { }` for fire-and-forget, `TaskGroup` for parallel work
- Never block the main thread with synchronous I/O

## SwiftUI
- Views must be lightweight — no business logic in body
- Business logic belongs in ViewModels (@Observable or ObservableObject)
- Networking and data access belong in Services
- Keep @State small and local to the view
- Avoid unnecessary @Published — only publish what views observe
- Use `.task` for async work on view appear, not `.onAppear` with Task

## Error Handling
- Use typed errors or Result at service boundaries
- Handle errors explicitly — no silent `try?` without justification
- Log errors before discarding them
- Never catch and ignore errors from network/API calls

## Code Organization
- One primary type per file
- Extensions for protocol conformances in the same file
- Group: properties, init, public methods, private methods
- Keep files under 300 lines — extract when larger
