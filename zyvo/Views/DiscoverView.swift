//
//  DiscoverView.swift
//  zyvo
//
//  Created by Claude Code
//

import SwiftUI

struct DiscoverView: View {
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
                VStack(spacing: 20) {
                    // Header
                    Text("Discover")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Search bar
                    searchBar

                    // Categories
                    categoriesSection

                    // Trending venues
                    trendingSection

                    Spacer(minLength: 40)
                }
            }
        }
    }
}

// MARK: - Components
private extension DiscoverView {
    var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))

            Text("Search venues, vibes, music...")
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    CategoryChip(icon: "music.note", label: "Live Music")
                    CategoryChip(icon: "wineglass", label: "Cocktail Bars")
                    CategoryChip(icon: "sparkles", label: "Clubs")
                    CategoryChip(icon: "building.2", label: "Rooftop")
                    CategoryChip(icon: "fork.knife", label: "Lounge")
                }
                .padding(.horizontal, 20)
            }
        }
    }

    var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending Now")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                TrendingVenueCard(
                    name: "The Blue Note",
                    type: "Jazz Club",
                    vibe: "Packed",
                    distance: "0.3 mi"
                )

                TrendingVenueCard(
                    name: "Skybar Rooftop",
                    type: "Rooftop Bar",
                    vibe: "Chill",
                    distance: "0.8 mi"
                )

                TrendingVenueCard(
                    name: "The Underground",
                    type: "Night Club",
                    vibe: "Electric",
                    distance: "1.2 mi"
                )
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Subviews
private struct CategoryChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)

            Text(label)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct TrendingVenueCard: View {
    let name: String
    let type: String
    let vibe: String
    let distance: String

    var body: some View {
        HStack(spacing: 12) {
            // Venue image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 70, height: 70)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.5))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(type)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                        Text(vibe)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2), in: Capsule())

                    Text(distance)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    DiscoverView()
}
