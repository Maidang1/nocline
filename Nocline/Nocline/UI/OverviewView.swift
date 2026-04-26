import SwiftUI

enum OverviewTab: String, CaseIterable, Identifiable {
    case usage = "Usage"
    case activity = "Activity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .usage: return "gauge.with.dots.needle.33percent"
        case .activity: return "calendar"
        }
    }
}

struct OverviewView: View {
    @ObservedObject private var codexUsageService = CodexUsageService.shared
    @ObservedObject private var codexActivityService = CodexActivityService.shared
    @State private var selectedTab: OverviewTab = .usage
    private static let activityAutoRefreshIntervalNanoseconds: UInt64 = 30 * 1_000_000_000

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(TerminalColors.border)
            contentArea
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(TerminalColors.panelBackground)
        .task {
            await codexUsageService.refreshIfNeeded()
        }
        .task(id: selectedTab) {
            await activityAutoRefreshLoop()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Overview")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TerminalColors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(OverviewTab.allCases) { tab in
                Button(action: { selectTab(tab) }) {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                            .foregroundColor(
                                selectedTab == tab
                                    ? TerminalColors.primaryText
                                    : TerminalColors.secondaryText
                            )
                            .frame(width: 20)

                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundColor(
                                selectedTab == tab
                                    ? TerminalColors.primaryText
                                    : TerminalColors.secondaryText
                            )

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                selectedTab == tab
                                    ? TerminalColors.subtleBackground
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 180)
        .padding(.horizontal, 8)
        .background(TerminalColors.panelBackground)
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            Divider().background(TerminalColors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .usage:
                        usageContent
                    case .activity:
                        activityContent
                    }
                }
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerBar: some View {
        HStack {
            Text(selectedTab.rawValue)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TerminalColors.primaryText)

            Spacer()

            Button(action: { OverviewWindowController.shared.hide() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TerminalColors.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(TerminalColors.subtleBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var usageContent: some View {
        let presentation = CodexUsageSectionPresentation.make(from: codexUsageService.state)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                statusBadge(
                    presentation.statusText,
                    color: usageStatusColor(for: codexUsageService.state)
                )
                Spacer()
                Button(action: refreshUsage) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            codexUsageService.state == .loading
                                ? TerminalColors.dimmedText
                                : TerminalColors.secondaryText
                        )
                        .frame(width: 20, height: 20)
                        .background(TerminalColors.controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(codexUsageService.state == .loading)
            }
            .padding(.horizontal, 20)

            usageCardsSection(presentation: presentation)
        }
    }

    private var activityContent: some View {
        let presentation = CodexActivityPresentation.make(from: codexActivityService.state)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                statusBadge(
                    activityStatusText(for: codexActivityService.state),
                    color: activityStatusColor(for: codexActivityService.state)
                )
                Text(activityRangeText(days: presentation.days))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TerminalColors.dimmedText)

                Spacer()

                Button(action: refreshActivity) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            codexActivityService.state == .loading
                                ? TerminalColors.dimmedText
                                : TerminalColors.secondaryText
                        )
                        .frame(width: 20, height: 20)
                        .background(TerminalColors.controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(codexActivityService.state == .loading)
            }
            .padding(.horizontal, 20)

            activitySummarySection(presentation: presentation)

            CodexActivityHeatmapView(presentation: presentation)
                .padding(.horizontal, 20)
        }
    }

    private func activitySummarySection(presentation: CodexActivityPresentation) -> some View {
        HStack(spacing: 10) {
            activityMetric(title: "Active Days", value: "\(presentation.activeDayCount)")
            activityMetric(title: "Today", value: presentation.todayTokenText)
            activityMetric(title: "Total", value: presentation.totalTokenText)
        }
        .padding(.horizontal, 20)
    }

    private func activityMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(TerminalColors.dimmedText)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(TerminalColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(TerminalColors.subtleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TerminalColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func usageCardsSection(presentation: CodexUsageSectionPresentation) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(presentation.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().background(TerminalColors.border)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TerminalColors.primaryText)

                        HStack(spacing: 6) {
                            Text(row.detailText)
                                .font(.system(size: 11))
                                .foregroundColor(TerminalColors.dimmedText)

                            if let badgeText = row.badgeText {
                                Text(badgeText)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(TerminalColors.amber)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(TerminalColors.amber.opacity(0.14))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Spacer()

                    Text(row.remainingText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalColors.primaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(TerminalColors.subtleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TerminalColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
    }

    private func usageStatusColor(for state: CodexUsageState) -> Color {
        switch state {
        case .idle, .loading:
            return TerminalColors.amber
        case .loaded(let snapshot):
            return snapshot.isFromCache ? TerminalColors.amber : TerminalColors.accent
        case .unavailable:
            return TerminalColors.red
        }
    }

    private func activityStatusText(for state: CodexActivityState) -> String {
        switch state {
        case .idle, .loading:
            return "Loading..."
        case .loaded:
            return "Local"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func activityStatusColor(for state: CodexActivityState) -> Color {
        switch state {
        case .idle, .loading:
            return TerminalColors.amber
        case .loaded:
            return TerminalColors.accent
        case .unavailable:
            return TerminalColors.red
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    private func refreshUsage() {
        Task {
            await codexUsageService.refresh()
        }
    }

    private func refreshActivity() {
        Task {
            await codexActivityService.refresh()
        }
    }

    private func selectTab(_ tab: OverviewTab) {
        selectedTab = tab
    }

    @MainActor
    private func activityAutoRefreshLoop() async {
        guard selectedTab == .activity else { return }

        await refreshActivityOnActivation()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.activityAutoRefreshIntervalNanoseconds)
            guard !Task.isCancelled, selectedTab == .activity else { return }
            await refreshActivitySilently()
        }
    }

    @MainActor
    private func refreshActivityOnActivation() async {
        switch codexActivityService.state {
        case .loading:
            return
        case .loaded:
            await codexActivityService.refresh(showsLoading: false)
        case .idle, .unavailable:
            await codexActivityService.refresh()
        }
    }

    @MainActor
    private func refreshActivitySilently() async {
        if case .loading = codexActivityService.state {
            return
        }
        await codexActivityService.refresh(showsLoading: false)
    }

    private func activityRangeText(days: [CodexActivityDay]) -> String {
        guard let start = days.first?.date,
              let end = days.last?.date else {
            return "Last 365 Days"
        }

        return "\(Self.activityDateFormatter.string(from: start)) - \(Self.activityDateFormatter.string(from: end))"
    }

    private static let activityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

private struct CodexActivityHeatmapView: View {
    let presentation: CodexActivityPresentation

    private let cellSize: CGFloat = 7
    private let cellSpacing: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 365 Days")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TerminalColors.primaryText)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    weekdayLabels

                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { row in
                                    if row < week.count, let day = week[row] {
                                        dayCell(day)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.clear)
                                            .frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 5) {
                Text("Less")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TerminalColors.dimmedText)

                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: level, totalTokens: level == 0 ? 0 : level))
                        .frame(width: cellSize, height: cellSize)
                }

                Text("More")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TerminalColors.dimmedText)
            }
        }
        .padding(16)
        .background(TerminalColors.subtleBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TerminalColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { index in
                Text(label(forWeekdayIndex: index))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(TerminalColors.dimmedText)
                    .frame(width: weekdayLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var weeks: [[CodexActivityDay?]] {
        guard let firstDay = presentation.days.first else { return [] }
        let calendar = Calendar.current
        let leadingEmptyDays = calendar.component(.weekday, from: firstDay.date) - 1
        var cells: [CodexActivityDay?] = Array(repeating: nil, count: max(0, leadingEmptyDays))
        cells.append(contentsOf: presentation.days.map(Optional.some))

        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }

    private func dayCell(_ day: CodexActivityDay) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color(for: level(for: day.totalTokens), totalTokens: day.totalTokens))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        day.totalTokens > 0
                            ? TerminalColors.border
                            : TerminalColors.border.opacity(0.6),
                        lineWidth: 0.5
                    )
            )
            .frame(width: cellSize, height: cellSize)
            .help(helpText(for: day))
    }

    private func level(for totalTokens: Int) -> Int {
        guard totalTokens > 0, presentation.maxDailyTokens > 0 else { return 0 }
        let ratio = Double(totalTokens) / Double(presentation.maxDailyTokens)
        switch ratio {
        case 0..<0.25:
            return 1
        case 0.25..<0.5:
            return 2
        case 0.5..<0.75:
            return 3
        default:
            return 4
        }
    }

    private func color(for level: Int, totalTokens: Int) -> Color {
        if totalTokens == 0 || level == 0 {
            return TerminalColors.heatmapEmpty
        }

        switch level {
        case 1:
            return TerminalColors.accentMuted.opacity(0.75)
        case 2:
            return TerminalColors.accent.opacity(0.45)
        case 3:
            return TerminalColors.accent.opacity(0.72)
        default:
            return TerminalColors.accentSoft
        }
    }

    private func helpText(for day: CodexActivityDay) -> String {
        [
            "\(Self.tooltipDateFormatter.string(from: day.date)) · \(CodexActivityPresentation.formatTokens(day.totalTokens)) tokens",
            "Input: \(CodexActivityPresentation.formatTokens(day.inputTokens))",
            "Output: \(CodexActivityPresentation.formatTokens(day.outputTokens))",
            "Reasoning: \(CodexActivityPresentation.formatTokens(day.reasoningOutputTokens))",
            "Cached: \(CodexActivityPresentation.formatTokens(day.cachedInputTokens))",
        ].joined(separator: "\n")
    }

    private func label(forWeekdayIndex index: Int) -> String {
        switch index {
        case 1:
            return "Mon"
        case 3:
            return "Wed"
        case 5:
            return "Fri"
        default:
            return ""
        }
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

#Preview {
    OverviewView()
}
