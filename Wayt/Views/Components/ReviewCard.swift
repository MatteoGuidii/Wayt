import SwiftUI

/// Full-width review card used in the reviews sheet.
struct ReviewCardFullWidth: View {

    let review: GoogleReview
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author row
            HStack(spacing: 8) {
                // Initial avatar
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(String(review.authorName.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(WaytTheme.secondaryText)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(review.authorName)
                        .font(WaytTheme.subheadFont)
                        .lineLimit(1)

                    Text(review.relativePublishTime)
                        .font(WaytTheme.badgeFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }

                Spacer()
            }

            // Stars
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= review.rating ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(i <= review.rating ? .orange : Color.gray.opacity(0.3))
                }
            }

            // Review text
            if !review.text.isEmpty {
                Text(review.text)
                    .font(WaytTheme.captionLightFont)
                    .lineLimit(isExpanded ? nil : 5)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                if review.text.count > 150 {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Text(isExpanded ? "Show less" : "Read more")
                            .font(WaytTheme.captionFont)
                            .foregroundStyle(WaytTheme.mapsBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .waytCard()
    }
}

// MARK: - Reviews Sheet

/// Standalone reviews sheet with filter state and Google Maps link.
struct ReviewsSheet: View {

    let reviews: [GoogleReview]
    let googleMapsUrl: String?
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ReviewFilter = .all

    private var filteredReviews: [GoogleReview] {
        switch filter {
        case .all:
            return reviews
        case .positive:
            return reviews.filter { $0.rating >= 4 }
        case .negative:
            return reviews.filter { $0.rating <= 2 }
        case .neutral:
            return reviews.filter { $0.rating == 3 }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                ScrollView {
                    if filteredReviews.isEmpty {
                        ContentUnavailableView(
                            "No \(filter.label) Reviews",
                            systemImage: "text.bubble",
                            description: Text("Try a different filter.")
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredReviews) { review in
                                ReviewCardFullWidth(review: review)
                            }

                            // Google Maps link
                            googleMapsFooter
                        }
                        .padding(WaytTheme.cardPadding)
                    }
                }
            }
            .background(WaytTheme.backgroundGradient)
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WaytTheme.mapsBlue)
                            .font(.title3)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReviewFilter.allCases, id: \.self) { item in
                    let count = countFor(item)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter = item
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.label)
                            if item != .all {
                                Text("(\(count))")
                            }
                        }
                        .font(WaytTheme.badgeFont)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filter == item
                            ? WaytTheme.mapsBlue
                            : Color(.tertiarySystemBackground))
                        .foregroundStyle(filter == item
                            ? .white
                            : WaytTheme.primaryText)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, WaytTheme.cardPadding)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var googleMapsFooter: some View {
        VStack(spacing: 8) {
            Text("Showing up to 5 reviews from Google")
                .font(WaytTheme.captionFont)
                .foregroundStyle(WaytTheme.secondaryText)

            if let urlString = googleMapsUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("See all reviews on Google Maps", systemImage: "arrow.up.right.square")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(WaytTheme.mapsBlue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func countFor(_ filter: ReviewFilter) -> Int {
        switch filter {
        case .all: reviews.count
        case .positive: reviews.filter { $0.rating >= 4 }.count
        case .negative: reviews.filter { $0.rating <= 2 }.count
        case .neutral: reviews.filter { $0.rating == 3 }.count
        }
    }
}

// MARK: - Review Filter

enum ReviewFilter: CaseIterable {
    case all, positive, neutral, negative

    var label: String {
        switch self {
        case .all: "All"
        case .positive: "Positive"
        case .neutral: "Neutral"
        case .negative: "Negative"
        }
    }
}
