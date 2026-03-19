import SwiftUI

struct ProfileEditSheet: View {

    @EnvironmentObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    let isFirstTime: Bool

    @State private var editedName: String = ""
    @State private var isSaving = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer().frame(height: 8)

                VenuuMascot(size: 80, expression: isFirstTime ? .looking : .happy, animated: false)

                Text(isFirstTime ? "What should we call you?" : "Edit Display Name")
                    .font(VenuuTheme.headlineFont)

                if isFirstTime {
                    Text("Pick a name that other users will see.")
                        .font(VenuuTheme.subtitleFont)
                        .foregroundStyle(VenuuTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Display name", text: $editedName)
                        .font(VenuuTheme.bodyFont)
                        .padding(14)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("\(editedName.trimmingCharacters(in: .whitespacesAndNewlines).count)/30")
                            .font(VenuuTheme.captionFont)
                            .foregroundStyle(nameValid ? Color.secondary : Color.red)
                        Spacer()
                        if !nameValid && !editedName.isEmpty {
                            Text("2-30 characters required")
                                .font(VenuuTheme.captionFont)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .font(VenuuTheme.calloutBoldFont)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: nameValid ? [VenuuTheme.skyPunch, VenuuTheme.ultraBlue] : [.gray],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .disabled(!nameValid || isSaving)
                .padding(.horizontal, 32)

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
        }
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
