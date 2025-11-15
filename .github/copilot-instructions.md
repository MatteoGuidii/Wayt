# GitHub Copilot Instructions for zyvo

## Project Overview
zyvo is an iOS application built with SwiftUI and integrated with AWS Amplify for authentication services. The app provides user authentication functionality using AWS Cognito.

## Technology Stack
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Backend**: AWS Amplify (Cognito for authentication)
- **Architecture**: MVVM with ObservableObject pattern
- **Minimum iOS Version**: iOS 15+ (implied by SwiftUI usage)

## Project Structure
```
zyvo/
├── zyvo/
│   ├── zyvoApp.swift           # App entry point, Amplify configuration
│   ├── Views/
│   │   ├── WelcomeView.swift
│   │   └── Auth/
│   │       ├── AuthView.swift
│   │       ├── AuthHeaderView.swift
│   │       ├── LoginView.swift
│   │       └── SignupView.swift
│   └── Managers/
│       └── AuthManager.swift    # Authentication business logic
├── zyvoTests/                   # Unit tests
├── zyvoUITests/                 # UI tests
└── amplify/                     # AWS Amplify configuration
```

## Code Style and Conventions

### Swift Conventions
- Use `private(set)` for properties that should be read-only externally
- Use `@MainActor` for classes that interact with UI
- Mark classes as `final` when they're not meant to be subclassed
- Use `@Published` properties for observable state in view models
- Use `@State` and `@EnvironmentObject` in views appropriately
- Prefer `async/await` over completion handlers for asynchronous operations
- Use `Task` blocks for asynchronous work in SwiftUI views

### Naming Conventions
- Use descriptive, self-documenting names
- Private methods and properties should be clearly marked with `private` or `private(set)`
- Use `is` prefix for Boolean properties (e.g., `isSignedIn`, `isSubmitting`)
- Use `handle` prefix for action methods (e.g., `handleLogin`, `handleSignup`)
- State properties use descriptive names without prefixes (e.g., `email`, `password`, `statusMessage`)

### SwiftUI View Structure
- Structure views with the following order:
  1. Property wrappers (`@State`, `@EnvironmentObject`, `@Environment`)
  2. Private constants (e.g., color definitions)
  3. Body property
  4. Preview
  5. Private extensions with helper methods
- Use `LinearGradient` backgrounds with opacity for consistent visual design
- Use `RoundedRectangle` with continuous corner style for form elements
- Maintain consistent spacing (16, 24, 32) and padding values
- Use `.opacity()` modifiers for color variations

### Authentication Patterns
- Email normalization: trim whitespace and convert to lowercase
- Use `AuthManager` as single source of truth for authentication state
- Handle async operations with proper error handling
- Show status messages for user feedback
- Use loading states (`isSubmitting`, `isConfirming`) to prevent duplicate submissions
- Always check form validity before enabling submit buttons

### State Management
- Use `@MainActor` for classes that manage UI state
- Use `@Published` properties for observable changes
- Update UI state within `MainActor.run` blocks when in async contexts
- Use environment objects for shared state (e.g., `AuthManager`)

### Error Handling
- Catch and display user-friendly error messages
- Use `localizedDescription` for displaying errors to users
- Handle specific AWS Amplify error cases (e.g., username exists)
- Provide informative status messages during multi-step processes

## AWS Amplify Integration

### Authentication Flow
1. **Sign Up**: Create account → Handle confirmation if required → Auto sign-in on success
2. **Confirmation**: Verify email with code → Sign in after confirmation
3. **Sign In**: Authenticate user → Update auth state
4. **Sign Out**: Clear session → Update auth state

### Key Amplify APIs
- `Amplify.Auth.signUp()` - Create new user
- `Amplify.Auth.confirmSignUp()` - Verify email with confirmation code
- `Amplify.Auth.signIn()` - Authenticate user
- `Amplify.Auth.signOut()` - End session
- `Amplify.Auth.fetchAuthSession()` - Check current session
- `Amplify.Auth.getCurrentUser()` - Get current user details
- `Amplify.Auth.resendSignUpCode()` - Resend confirmation code

### Amplify Configuration
- Configured in `zyvoApp.init()` with `AWSCognitoAuthPlugin`
- Configuration files are gitignored (amplifyconfiguration.json, etc.)
- Backend configuration is in `amplify/` directory

## Testing
- Unit tests: `zyvoTests/`
- UI tests: `zyvoUITests/`
- Use `#Preview` macros for SwiftUI view previews
- Mock `AuthManager` in previews with `@StateObject` or `@EnvironmentObject`

## Build and Deployment
- Project uses Xcode project format (`.xcodeproj`)
- npm dependencies managed for Amplify CLI
- Amplify backend managed via Amplify CLI

## Security Considerations
- Never commit AWS configuration files (already in .gitignore)
- Email addresses are normalized (trimmed and lowercased) for consistency
- Passwords are handled securely through AWS Cognito
- Use `SecureField` for password inputs
- Never log sensitive user data

## Common Patterns to Follow
1. **Async/Await in Views**: Always use `Task` blocks and handle main actor updates
2. **Form Validation**: Implement `isFormValid` computed properties
3. **Loading States**: Track submission states to prevent duplicate requests
4. **Dismissal**: Use `@Environment(\.dismiss)` for view dismissal
5. **Error Display**: Show status messages inline with forms
6. **Multi-step Flows**: Handle confirmation codes and additional steps gracefully

## When Making Changes
- Maintain consistency with existing code style
- Test authentication flows end-to-end
- Ensure proper error handling for AWS Amplify operations
- Keep UI responsive with loading indicators
- Maintain accessibility features (use system fonts, proper contrast)
- Follow SwiftUI best practices for state management
- Keep view logic in private extensions for clarity
