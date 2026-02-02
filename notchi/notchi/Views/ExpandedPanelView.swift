import SwiftUI

struct ExpandedPanelView: View {
    let state: NotchiState
    let stats: SessionStats
    let usageService: ClaudeUsageService
    let onSettingsTap: () -> Void

    private var isWorking: Bool {
        stats.isProcessing && state != .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if !stats.recentEvents.isEmpty || stats.isProcessing {
                Divider().background(Color.white.opacity(0.08))
                activitySection
            }

            if stats.sessionStartTime == nil && stats.recentEvents.isEmpty {
                Spacer()
                emptyState
                Spacer()
            }

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

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(stats.recentEvents) { event in
                                ActivityRowView(event: event)
                                    .id(event.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .onAppear {
                        if let id = stats.recentEvents.last?.id {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onChange(of: stats.recentEvents.last?.id) { _, newId in
                        if let id = newId {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }
                }

                VStack {
                    fadeGradient(direction: .top)
                    Spacer()
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
