import SwiftUI

struct StreakStrip: View {

    let currentStreak: Int
    /// Last 4 weeks, each element is an array of "yyyy-MM-dd" date strings (Mon–Sun).
    let last4Weeks: [[String]]
    let reportDates: [String]
    var remainingFreezes: Int = 0

    @State private var showCalendar = false

    static let flameOrange = Color(red: 1.0, green: 0.60, blue: 0.0)
    static let freezeBlue = Color(red: 0.40, green: 0.75, blue: 1.0)

    var body: some View {
        Button { showCalendar = true } label: {
            HStack(spacing: 14) {
                // Flame icon — Duolingo-style orange when active
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(currentStreak > 0 ? Self.flameOrange : Color(.systemGray3))

                // Streak count
                VStack(alignment: .leading, spacing: 2) {
                    if currentStreak > 0 {
                        HStack(spacing: 4) {
                            Text("\(currentStreak)")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                            + Text(" week streak")
                                .font(WaytTheme.subheadLightFont)

                            if remainingFreezes > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "snowflake")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(remainingFreezes)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(Self.freezeBlue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Self.freezeBlue.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text("No streak yet")
                            .font(WaytTheme.subheadLightFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                }

                Spacer()

                // Weekly squares
                HStack(spacing: 6) {
                    ForEach(Array(last4Weeks.enumerated()), id: \.offset) { index, weekDates in
                        let isCurrentWeek = index == last4Weeks.count - 1
                        let hasReport = weekDates.contains(where: { reportDates.contains($0) })

                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(hasReport ? Self.flameOrange : Color(.systemGray5))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if hasReport {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .black))
                                            .foregroundStyle(.white)
                                    }
                                }

                            if isCurrentWeek {
                                Circle()
                                    .fill(Self.flameOrange)
                                    .frame(width: 4, height: 4)
                            } else {
                                Spacer().frame(height: 4)
                            }
                        }
                    }

                    // Chevron hint
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WaytTheme.secondaryText)
                        .padding(.bottom, 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(WaytTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCalendar) {
            StreakCalendarSheet(
                currentStreak: currentStreak,
                reportDates: Set(reportDates),
                remainingFreezes: remainingFreezes
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
