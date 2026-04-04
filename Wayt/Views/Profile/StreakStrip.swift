import SwiftUI

struct StreakStrip: View {

    let currentStreak: Int
    let currentWeekDays: [ProfileViewModel.WeekDay]
    let reportDates: [String]
    var remainingFreezes: Int = 0
    var freezesUsed: Int = 0
    #if DEBUG
    var onSeedScenario: ((ProfileViewModel.StreakScenario) -> Void)?
    #endif

    @State private var showCalendar = false

    static let flameOrange = Color(red: 1.0, green: 0.60, blue: 0.0)
    static let freezeBlue = Color(red: 0.40, green: 0.75, blue: 1.0)

    private var streakSubtitle: String {
        switch currentStreak {
        case 0: return "Submit a report to start your streak"
        case 1: return "Keep it going — report again this week!"
        case 2...4: return "You're building momentum!"
        case 5...11: return "On fire — don't stop now!"
        default: return "Legendary consistency!"
        }
    }

    var body: some View {
        Button { showCalendar = true } label: {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(currentStreak > 0 ? Self.flameOrange : Color(.systemGray3))

                    VStack(alignment: .leading, spacing: 2) {
                        if currentStreak > 0 {
                            Text("\(currentStreak)-week streak")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(WaytTheme.primaryText)
                        } else {
                            Text("No streak yet")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(WaytTheme.secondaryText)
                        }

                        Text(streakSubtitle)
                            .font(WaytTheme.captionLightFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }

                    Spacer()
                }

                weekRow

                if remainingFreezes > 0 || freezesUsed > 0 || currentStreak >= 3 {
                    freezeSection
                }
            }
            .padding(16)
            .background(WaytTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        #if DEBUG
        .contextMenu {
            if let onSeed = onSeedScenario {
                ForEach(ProfileViewModel.StreakScenario.allCases, id: \.self) { scenario in
                    Button(scenario.rawValue) { onSeed(scenario) }
                }
            }
        }
        #endif
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

    // MARK: - Week Row

    private let circleSize: CGFloat = 32

    private var weekRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(currentWeekDays) { day in
                    Text(day.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WaytTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            ZStack {
                GeometryReader { geo in
                    let step = geo.size.width / 7
                    let y = circleSize / 2
                    ForEach(1..<currentWeekDays.count, id: \.self) { i in
                        let x1 = step * CGFloat(i - 1) + step / 2
                        let x2 = step * CGFloat(i) + step / 2
                        Rectangle()
                            .fill(lineColor(before: i))
                            .frame(width: x2 - x1, height: 3)
                            .position(x: (x1 + x2) / 2, y: y)
                    }
                }
                .frame(height: circleSize)

                HStack(spacing: 0) {
                    ForEach(currentWeekDays) { day in
                        ZStack {
                            Circle()
                                .fill(day.hasReport ? Self.flameOrange : Color(.systemGray5))
                                .frame(width: circleSize, height: circleSize)

                            if day.isToday && !day.hasReport {
                                Circle()
                                    .stroke(Self.flameOrange.opacity(0.6), lineWidth: 2)
                                    .frame(width: circleSize, height: circleSize)
                            }

                            if day.hasReport {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func lineColor(before index: Int) -> Color {
        guard index > 0, index < currentWeekDays.count else { return Color(.systemGray5) }
        let prev = currentWeekDays[index - 1]
        let curr = currentWeekDays[index]
        if prev.hasReport && curr.hasReport {
            return Self.flameOrange
        }
        return Color(.systemGray5)
    }

    // MARK: - Freeze Section

    private var freezeSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Self.freezeBlue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    VStack(spacing: 1) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Self.freezeBlue)
                        Text("\(remainingFreezes)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Self.freezeBlue)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if remainingFreezes > 0 {
                        Text("\(remainingFreezes) Streak Freeze\(remainingFreezes == 1 ? "" : "s")")
                            .font(WaytTheme.subheadFont)
                            .foregroundStyle(WaytTheme.primaryText)
                    } else {
                        Text("No Freezes Available")
                            .font(WaytTheme.subheadFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }

                    Text("Activates automatically if you miss a week")
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }

                Spacer()
            }

            if freezesUsed > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Self.freezeBlue)
                    Text("\(freezesUsed) freeze\(freezesUsed == 1 ? "" : "s") protecting your streak right now")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(Self.freezeBlue)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Self.freezeBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if remainingFreezes == 0 && freezesUsed == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WaytTheme.secondaryText)
                    Text("Report 3 weeks in a row to earn a freeze")
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
