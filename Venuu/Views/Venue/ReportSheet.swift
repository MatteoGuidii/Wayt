import SwiftUI

struct ReportSheet: View {

    let venue: Venue
    let onSubmit: (BusynessLevel, Int?) -> Void

    @State private var selectedLevel: BusynessLevel?
    @State private var waitMinutes: Double = 0
    @State private var includeWaitTime: Bool = false
    @State private var submitted: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("How busy is")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(venue.name)
                        .font(VenuuTheme.headlineFont)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("right now?")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Busyness level picker
                HStack(spacing: 10) {
                    ForEach(BusynessLevel.allCases, id: \.self) { level in
                        levelButton(level)
                    }
                }
                .padding(.horizontal, 4)

                // Optional wait time
                VStack(spacing: 10) {
                    Toggle("Include wait time", isOn: $includeWaitTime)
                        .font(VenuuTheme.captionFont)
                        .tint(VenuuTheme.primaryPurple)

                    if includeWaitTime {
                        VStack(spacing: 4) {
                            Text("\(Int(waitMinutes)) min")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(VenuuTheme.primaryPurple)

                            Slider(value: $waitMinutes, in: 0...90, step: 5)
                                .tint(VenuuTheme.primaryPurple)

                            HStack {
                                Text("No wait")
                                    .font(VenuuTheme.badgeFont)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("90+ min")
                                    .font(VenuuTheme.badgeFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Submit button
                Button {
                    guard let level = selectedLevel else { return }
                    let wait = includeWaitTime ? Int(waitMinutes) : nil
                    onSubmit(level, wait)
                    submitted = true

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    // Dismiss after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        dismiss()
                    }
                } label: {
                    Group {
                        if submitted {
                            Label("Submitted!", systemImage: "checkmark.circle.fill")
                        } else {
                            Text("Submit Report")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(submitted ? .green : (selectedLevel != nil ? VenuuTheme.primaryPurple : .gray))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(selectedLevel == nil || submitted)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Level Button

    private func levelButton(_ level: BusynessLevel) -> some View {
        let isSelected = selectedLevel == level
        return Button {
            withAnimation(.spring(response: 0.25)) {
                selectedLevel = level
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: level.icon)
                    .font(.system(size: 22))
                Text(level.label)
                    .font(VenuuTheme.badgeFont)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? level.color.opacity(0.20) : Color(.tertiarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? level.color : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(isSelected ? level.color : .primary)
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
