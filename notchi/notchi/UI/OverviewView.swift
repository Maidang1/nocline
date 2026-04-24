import SwiftUI

struct OverviewView: View {
    @ObservedObject private var codexUsageService = CodexUsageService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(TerminalColors.border)
            usageContent
            Spacer()
        }
        .frame(width: 500, height: 450)
        .background(TerminalColors.panelBackground)
        .task {
            await codexUsageService.refreshIfNeeded()
        }
    }

    private var titleBar: some View {
        HStack {
            Text("Codex Usage")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var usageContent: some View {
        let presentation = CodexUsageSectionPresentation.make(from: codexUsageService.state)

        return VStack(alignment: .leading, spacing: 12) {
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
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(codexUsageService.state == .loading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            usageCardsSection(presentation: presentation)
        }
    }

    private func usageCardsSection(presentation: CodexUsageSectionPresentation) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(presentation.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().background(Color.white.opacity(0.06))
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
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
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
}

#Preview {
    OverviewView()
}