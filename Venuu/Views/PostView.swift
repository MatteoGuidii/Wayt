//
//  PostView.swift
//  Venuu
//
//  Created by Claude Code
//

import SwiftUI

struct PostView: View {
    @State private var selectedVenue = "Select Venue"
    @State private var crowdLevel = 2
    @State private var musicEnergy = 2
    @State private var waitTime = 1
    @State private var vibeText = ""
    @State private var showValidationError = false
    @State private var validationMessage = ""

    private let maxVibeLength = 500

    var body: some View {
        ZStack {
            // Purple-blue gradient background
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.3),
                    Color.blue.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    Text("Post Update")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Venue selection
                    venueSelector

                    // Crowd level
                    sliderCard(
                        title: "Crowd Level",
                        icon: "person.3.fill",
                        value: $crowdLevel,
                        labels: ["Empty", "Moderate", "Packed"]
                    )

                    // Music energy
                    sliderCard(
                        title: "Music Energy",
                        icon: "music.note",
                        value: $musicEnergy,
                        labels: ["Chill", "Vibing", "Electric"]
                    )

                    // Wait time
                    sliderCard(
                        title: "Wait Time",
                        icon: "clock.fill",
                        value: $waitTime,
                        labels: ["None", "Short", "Long"]
                    )

                    // Vibe description
                    vibeInput

                    // Post button
                    postButton

                    Spacer(minLength: 40)
                }
            }
        }
    }
}

// MARK: - Components
private extension PostView {
    var venueSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Venue")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 20)

            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.purple)

                Text(selectedVenue)
                    .foregroundStyle(selectedVenue == "Select Venue" ? .white.opacity(0.4) : .white)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    func sliderCard(title: String, icon: String, value: Binding<Int>, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.purple)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(labels[value.wrappedValue])
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2), in: Capsule())
            }

            HStack {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index <= value.wrappedValue ? Color.purple : Color.white.opacity(0.2))
                        .frame(width: 12, height: 12)
                        .onTapGesture {
                            value.wrappedValue = index
                        }

                    if index < 2 {
                        Rectangle()
                            .fill(index < value.wrappedValue ? Color.purple : Color.white.opacity(0.2))
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    var vibeInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Describe the Vibe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text("\(vibeText.count)/\(maxVibeLength)")
                    .font(.caption)
                    .foregroundStyle(vibeText.count > maxVibeLength ? .red : .white.opacity(0.5))
            }
            .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                if vibeText.isEmpty {
                    Text("What's the atmosphere like? Any special events?")
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(16)
                }

                TextEditor(text: $vibeText)
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(height: 100)
                    .padding(12)
                    .onChange(of: vibeText) { oldValue, newValue in
                        if newValue.count > maxVibeLength {
                            vibeText = String(newValue.prefix(maxVibeLength))
                        }
                    }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    var postButton: some View {
        VStack(spacing: 8) {
            Button(action: handlePostAction) {
                HStack {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))

                    Text("Post Update")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: isPostValid ? [Color.purple, Color.blue] : [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: .purple.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .disabled(!isPostValid)

            if showValidationError {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var isPostValid: Bool {
        selectedVenue != "Select Venue" && !vibeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handlePostAction() {
        guard isPostValid else {
            validationMessage = "Please select a venue and add a description"
            showValidationError = true
            return
        }

        // TODO: Implement actual post submission logic here
        // For now, just show success feedback
        showValidationError = false
        print("Post submitted: \(selectedVenue), Vibe: \(vibeText)")
    }
}

#Preview {
    PostView()
}
