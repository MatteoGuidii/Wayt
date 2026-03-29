import SwiftUI

struct StreakStrip: View {

    let currentStreak: Int
    /// Last 4 weeks, each element is an array of "yyyy-MM-dd" date strings (Mon–Sun).
    let last4Weeks: [[String]]
    let reportDates: [String]

    @State private var showCalendar = false

    static let flameOrange = Color(red: 1.0, green: 0.60, blue: 0.0)

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
                        Text("\(currentStreak)")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                        + Text(" week streak")
                            .font(WaytTheme.subheadLightFont)
                    } else {
                        Text("No streak yet")
                            .font(WaytTheme.subheadLightFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                }

                Spacer()

                // 4-week squares
                HStack(spacing: 4) {
                    Text("4W")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WaytTheme.secondaryText)
                        .padding(.trailing, 2)

                    ForEach(Array(last4Weeks.enumerated()), id: \.offset) { index, weekDates in
                        let isCurrentWeek = index == last4Weeks.count - 1
                        let hasReport = weekDates.contains(where: { reportDates.contains($0) })

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
                            .overlay {
                                if isCurrentWeek {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Self.flameOrange.opacity(0.5), lineWidth: 2)
                                        .frame(width: 23, height: 23)
                                }
                            }
                    }

                    // Chevron hint
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WaytTheme.secondaryText)
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
                reportDates: Set(reportDates)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
