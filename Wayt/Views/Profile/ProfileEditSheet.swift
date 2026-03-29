import SwiftUI

struct ProfileEditSheet: View {

    @EnvironmentObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    let isFirstTime: Bool

    @State private var editedName: String = ""
    @State private var isSaving = false
    @State private var showError = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 8)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(WaytTheme.skyPunch)

                Text(isFirstTime ? "What should we call you?" : "Edit Display Name")
                    .font(WaytTheme.headlineFont)

                if isFirstTime {
                    Text("Pick a name that other users will see.")
                        .font(WaytTheme.subtitleFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                nameField

                saveButton

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstTime {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(isFirstTime)
            .alert("Couldn't save name", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text("Please try again.")
            }
        }
        .onAppear {
            editedName = viewModel.displayName ?? ""
            // Delay focus slightly so the sheet animation completes first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isFieldFocused = true
            }
        }
    }

    // MARK: - Subviews (isolated to limit re-render scope)

    private var nameField: some View {
        let trimmedCount = editedName.trimmingCharacters(in: .whitespacesAndNewlines).count
        let valid = trimmedCount >= 2 && trimmedCount <= 30

        return VStack(alignment: .leading, spacing: 6) {
            TextField("Display name", text: $editedName)
                .font(WaytTheme.bodyFont)
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($isFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    guard valid, !isSaving else { return }
                    Task { await save() }
                }

            HStack {
                Text("\(trimmedCount)/30")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(valid ? Color.secondary : Color.red)
                Spacer()
                if !valid && !editedName.isEmpty {
                    Text("2-30 characters required")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var saveButton: some View {
        let valid = nameValid

        return Button {
            Task { await save() }
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Save")
                        .font(WaytTheme.calloutBoldFont)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: valid ? [WaytTheme.skyPunch, WaytTheme.ultraBlue] : [.gray],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
        .disabled(!valid || isSaving)
        .padding(.horizontal, 32)
    }

    private var nameValid: Bool {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 30
    }

    private func save() async {
        isSaving = true
        let success = await viewModel.updateDisplayName(editedName)
        isSaving = false

        if success {
            authState.updateDisplayName(editedName.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } else {
            showError = true
        }
    }
}
