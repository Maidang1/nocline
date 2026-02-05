import SwiftUI

struct UsageBarView: View {
    let usage: QuotaPeriod?
    let isLoading: Bool
    let error: String?
    let onSettingsTap: () -> Void

    private var isStale: Bool {
        error != nil && usage != nil
    }

    private var usageColor: Color {
        guard let usage else { return TerminalColors.dimmedText }
        if isStale { return TerminalColors.dimmedText }
        switch usage.usagePercentage {
        case ..<50: return TerminalColors.green
        case ..<80: return TerminalColors.amber
        default: return TerminalColors.red
        }
    }

    var body: some View {
        if KeychainManager.hasCredentials {
            connectedView
        } else {
            unconfiguredView
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let error, usage == nil {
                    Button(action: onSettingsTap) {
                        HStack(spacing: 4) {
                            Text(error)
                            Text("– Tap to fix")
                                .foregroundColor(TerminalColors.secondaryText)
                        }
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.red)
                    }
                    .buttonStyle(.plain)
                } else if let usage, let resetTime = usage.formattedResetTime {
                    HStack(spacing: 4) {
                        Text("Resets in \(resetTime)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TerminalColors.secondaryText)
                        if isStale {
                            Text("(cached)")
                                .font(.system(size: 10))
                                .foregroundColor(TerminalColors.dimmedText)
                        }
                    }
                } else {
                    Text("Claude Usage")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.secondaryText)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else if let usage {
                    Text("\(usage.usagePercentage)%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(usageColor)
                }
            }

            progressBar
        }
        .padding(.top, 5)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(TerminalColors.subtleBackground)

                if let usage {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(usageColor)
                        .frame(width: geometry.size.width * Double(usage.usagePercentage) / 100)
                }
            }
        }
        .frame(height: 4)
    }

    private var unconfiguredView: some View {
        Button(action: onSettingsTap) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 11))
                Text("Configure usage tracking")
                    .font(.system(size: 11))
            }
            .foregroundColor(TerminalColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(TerminalColors.subtleBackground)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.top, 5)
    }
}
