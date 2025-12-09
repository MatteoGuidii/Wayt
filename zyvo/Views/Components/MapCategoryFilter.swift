import SwiftUI

/// Floating category filter chips that appear at the top of the map for real-time filtering
struct MapCategoryFilter: View {
    @Binding var selectedCategories: Set<VenueType>
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 12) {
            // Toggle button
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.title3)
                        Text(filterText)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)

                // Clear filters button (only show when filtering)
                if !selectedCategories.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategories.removeAll()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Filter chips
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
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
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.subheadline.weight(.semibold))
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : type.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? type.color : Color(uiColor: .systemBackground))
                    .shadow(color: isSelected ? type.color.opacity(0.4) : .black.opacity(0.1), radius: isSelected ? 8 : 4, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : type.color.opacity(0.3), lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
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
