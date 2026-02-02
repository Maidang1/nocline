import SwiftUI

struct ExpandedPanelView: View {
    let state: NotchiState
    let stats: SessionStats
    let usageService: ClaudeUsageService
    let onSettingsTap: () -> Void

    private var isWorking: Bool {
        state == .working || state == .thinking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if !stats.recentEvents.isEmpty || stats.isProcessing {
                Divider().background(Color.white.opacity(0.08))
                activitySection
            }

            if stats.sessionStartTime == nil && stats.recentEvents.isEmpty {
                emptyState
            }

            Spacer()

            UsageBarView(
                usage: usageService.currentUsage,
                isLoading: usageService.isLoading,
                error: usageService.error,
                onSettingsTap: onSettingsTap
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            if isWorking {
                ProcessingSpinner()
            }
            Text(state.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.bottom, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWorking)
    }

    private var completedEvents: [SessionEvent] {
        stats.recentEvents.filter { $0.status != .running }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(completedEvents) { event in
                            ActivityRowView(event: event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)

                VStack {
                    fadeGradient(direction: .top)
                    Spacer()
                    fadeGradient(direction: .bottom)
                }
                .allowsHitTesting(false)
            }

            if isWorking {
                WorkingIndicatorView()
                    .padding(.top, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Waiting for activity")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)
            Text("Use a tool in Claude Code to start tracking")
                .font(.system(size: 12))
                .foregroundColor(TerminalColors.dimmedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func fadeGradient(direction: Edge) -> some View {
        LinearGradient(
            colors: [.black, .clear],
            startPoint: direction == .top ? .top : .bottom,
            endPoint: direction == .top ? .bottom : .top
        )
        .frame(height: 16)
    }
}
