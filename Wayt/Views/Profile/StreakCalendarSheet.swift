import SwiftUI

struct StreakCalendarSheet: View {

    let currentStreak: Int
    let reportDates: Set<String>
    var remainingFreezes: Int = 0

    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Current month first, then older months.
    private var monthsToShow: [Date] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<3).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: now)
        }
    }

    private var hasAnyReports: Bool {
        !reportDates.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    streakHeader

                    ForEach(monthsToShow, id: \.timeIntervalSince1970) { month in
                        monthView(for: month)
                    }

                    Spacer().frame(height: 16)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(WaytTheme.backgroundGradient.ignoresSafeArea())
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
    }

    // MARK: - Streak Header

    private var streakHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(currentStreak > 0 ? StreakStrip.flameOrange : Color(.systemGray3))

            if currentStreak > 0 {
                Text("\(currentStreak) week\(currentStreak == 1 ? "" : "s")")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text("Current streak")
                    .font(WaytTheme.subheadLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            } else if hasAnyReports {
                Text("Streak lost")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(WaytTheme.secondaryText)
                Text("Report again to start a new one")
                    .font(WaytTheme.subheadLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            } else {
                Text("No streak yet")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(WaytTheme.secondaryText)
                Text("Submit your first report to start")
                    .font(WaytTheme.subheadLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            if remainingFreezes > 0 || currentStreak >= 3 {
                VStack(spacing: 8) {
                    if remainingFreezes > 0 {
                        HStack(spacing: 8) {
                            ForEach(0..<remainingFreezes, id: \.self) { _ in
                                ZStack {
                                    Circle()
                                        .fill(StreakStrip.freezeBlue.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "snowflake")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(StreakStrip.freezeBlue)
                                }
                            }
                        }

                        Text("\(remainingFreezes) streak freeze\(remainingFreezes == 1 ? "" : "s") ready to use")
                            .font(WaytTheme.captionFont)
                            .foregroundStyle(WaytTheme.primaryText)
                    } else {
                        Image(systemName: "snowflake")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StreakStrip.freezeBlue)

                        Text("Earn a freeze every 3 consecutive weeks")
                            .font(WaytTheme.captionFont)
                            .foregroundStyle(WaytTheme.primaryText)
                    }

                    Text("Freezes protect your streak if you miss a week")
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(StreakStrip.freezeBlue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Month View

    private func monthView(for month: Date) -> some View {
        let calendar = Calendar.current
        let title = Self.monthYearFormatter.string(from: month)
        let days = daysInMonth(for: month)
        let firstWeekday = calendar.component(.weekday, from: days.first ?? month)
        let leadingBlanks = (firstWeekday + 5) % 7
        let monthHasReports = days.contains { reportDates.contains(Self.dateFormatter.string(from: $0)) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                if monthHasReports {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(StreakStrip.flameOrange)
                }
            }

            let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { i, label in
                    Text(label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WaytTheme.secondaryText)
                        .frame(height: 18)
                        .id("header-\(i)")
                }

                ForEach(0..<leadingBlanks, id: \.self) { i in
                    Color.clear.frame(height: 38)
                        .id("blank-\(i)")
                }

                ForEach(days, id: \.timeIntervalSince1970) { date in
                    let dateString = Self.dateFormatter.string(from: date)
                    let isFuture = date > Date()
                    let hasReport = !isFuture && reportDates.contains(dateString)
                    let isToday = calendar.isDateInToday(date)
                    let dayNumber = calendar.component(.day, from: date)

                    ZStack {
                        if hasReport {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(StreakStrip.flameOrange)
                                .frame(width: 38, height: 38)
                        } else if isToday {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(StreakStrip.flameOrange.opacity(0.4), lineWidth: 2)
                                .frame(width: 38, height: 38)
                        }

                        Text("\(dayNumber)")
                            .font(.system(size: 15, weight: hasReport ? .bold : .medium, design: .rounded))
                            .foregroundStyle(
                                hasReport ? .white :
                                isFuture ? WaytTheme.secondaryText.opacity(0.3) :
                                WaytTheme.primaryText
                            )
                    }
                    .frame(height: 38)
                }
            }
        }
        .padding(16)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
    }

    // MARK: - Helpers

    private func daysInMonth(for date: Date) -> [Date] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return [] }

        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
    }
}
