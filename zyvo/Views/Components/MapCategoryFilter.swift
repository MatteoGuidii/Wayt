import SwiftUI

/// Floating category filter chips that appear at the top of the map for real-time filtering
struct MapCategoryFilter: View {
    @Binding var selectedCategories: Set<VenueType>
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 14) {
            // Enhanced toggle button with better visual hierarchy
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        // Icon with gradient background
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.8), .purple.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)

                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Text(filterText)
                            .font(.subheadline.weight(.bold))

                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)

                // Enhanced clear filters button
                if !selectedCategories.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategories.removeAll()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)

                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.red.opacity(0.8), .red],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Enhanced filter chips with better scrolling
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(VenueType.allCases, id: \.self) { type in
                            FilterChip(
                                type: type,
                                isSelected: selectedCategories.contains(type)
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedCategories.contains(type) {
                                        selectedCategories.remove(type)
                                    } else {
                                        selectedCategories.insert(type)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 60)
    }

    private var filterText: String {
        if selectedCategories.isEmpty {
            return "All Venues"
        } else if selectedCategories.count == 1 {
            return selectedCategories.first?.rawValue ?? "Filter"
        } else {
            return "\(selectedCategories.count) Types"
        }
    }
}

private struct FilterChip: View {
    let type: VenueType
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(type.rawValue)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(isSelected ? .white : type.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [type.color, type.color.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Capsule()
                            .fill(Color(uiColor: .systemBackground))
                    }
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [type.color.opacity(0.4), type.color.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? type.color.opacity(0.5) : .black.opacity(0.12),
                radius: isSelected ? 10 : 6,
                x: 0,
                y: isSelected ? 4 : 3
            )
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}
