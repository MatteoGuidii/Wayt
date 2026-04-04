import SwiftUI
import UIKit

struct AuthFieldView: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var hint: String? = nil
    var onSubmit: (() -> Void)? = nil

    @State private var showingPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(WaytTheme.subtitleFont)
                .foregroundStyle(WaytTheme.secondaryText)

            HStack(spacing: 0) {
                if isSecure {
                    PasswordTextField(
                        text: $text,
                        placeholder: placeholder,
                        hideText: !showingPassword,
                        contentType: textContentType,
                        onSubmit: onSubmit
                    )
                    .frame(height: 25)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .font(WaytTheme.bodyFont)
                }

                if isSecure && !text.isEmpty {
                    Button {
                        showingPassword.toggle()
                    } label: {
                        Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(WaytTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onSubmit { onSubmit?() }
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty { showingPassword = false }
            }

            if let hint {
                Text(hint)
                    .font(WaytTheme.captionLightFont)
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
    }
}

// MARK: - Password UITextField (renders bullets natively, suppresses password autofill)

private let bullet: Character = "\u{25CF}"

private struct PasswordTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var hideText: Bool
    var contentType: UITextContentType?
    var onSubmit: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.textContentType = contentType ?? .oneTimeCode
        field.passwordRules = nil
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.rounded)?
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]])
        field.font = desc.map { UIFont(descriptor: $0, size: 16) }
            ?? UIFont.systemFont(ofSize: 16, weight: .medium)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        let coord = context.coordinator
        let hideTextChanged = coord.hideText != hideText
        coord.hideText = hideText

        // While actively editing, only react to eye-toggle — don't re-set field.text
        // from the async binding echo, which would reset the cursor position.
        if field.isFirstResponder && !hideTextChanged {
            return
        }

        // Sync real text from binding (e.g. when reset externally via viewModel.reset())
        if coord.realText != text {
            coord.realText = text
        }

        let canonical = coord.realText
        let expected = hideText ? String(repeating: bullet, count: canonical.count) : canonical
        if field.text != expected {
            field.text = expected
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PasswordTextField
        var realText = ""
        var hideText = false

        init(_ parent: PasswordTextField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let nsReal = realText as NSString
            realText = nsReal.replacingCharacters(in: range, with: string)
            let updated = realText
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updated
            }

            if hideText {
                textField.text = String(repeating: bullet, count: realText.count)
                let newCursorPos = range.location + string.count
                if let pos = textField.position(from: textField.beginningOfDocument, offset: newCursorPos) {
                    textField.selectedTextRange = textField.textRange(from: pos, to: pos)
                }
                return false
            }

            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit?()
            return true
        }
    }
}

// MARK: - Auth Button

struct AuthPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(WaytTheme.calloutBoldFont)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(WaytTheme.mapsBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Banners

struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(WaytTheme.captionFont)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AuthInfoBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(WaytTheme.captionFont)
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WaytTheme.mapsBlue.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
