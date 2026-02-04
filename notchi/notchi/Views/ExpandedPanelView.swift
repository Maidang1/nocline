import SwiftUI

enum ActivityItem: Identifiable {
    case tool(SessionEvent)
    case assistant(AssistantMessage)

    var id: String {
        switch self {
        case .tool(let event): return "tool-\(event.id.uuidString)"
        case .assistant(let msg): return "assistant-\(msg.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case .tool(let event): return event.timestamp
        case .assistant(let msg): return msg.timestamp
        }
    }
}

struct ExpandedPanelView: View {
    let state: NotchiState
    let stats: SessionStats
    let usageService: ClaudeUsageService
    @Binding var showingSettings: Bool
    let onSettingsTap: () -> Void

    private var showIndicator: Bool {
        switch state {
        case .idle, .sleeping, .happy:
            return false
        case .thinking, .working, .alert, .compacting:
            return true
        }
    }

    private var hasActivity: Bool {
        !stats.recentEvents.isEmpty || !stats.recentAssistantMessages.isEmpty || stats.isProcessing || showIndicator || stats.lastUserPrompt != nil
    }

    private var unifiedActivityItems: [ActivityItem] {
        let toolItems = stats.recentEvents.map { ActivityItem.tool($0) }
        let messageItems = stats.recentAssistantMessages.map { ActivityItem.assistant($0) }
        return (toolItems + messageItems).sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        GeometryReader { geometry in
            if showingSettings {
                PanelSettingsView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                activityContent(geometry: geometry)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingSettings)
    }

    @ViewBuilder
    private func activityContent(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: geometry.size.height * 0.3)

            VStack(alignment: .leading, spacing: 0) {
                if hasActivity {
                    Divider().background(Color.white.opacity(0.08))
                    activitySection
                } else {
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
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)
                .padding(.top, 12)
                .padding(.bottom, 5)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let prompt = stats.lastUserPrompt {
                            UserPromptBubbleView(text: prompt)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.bottom, 8)
                        }

                        ForEach(unifiedActivityItems) { item in
                            switch item {
                            case .tool(let event):
                                ActivityRowView(event: event)
                                    .id(item.id)
                            case .assistant(let message):
                                AssistantTextRowView(message: message)
                                    .id(item.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .onAppear {
                    if let lastItem = unifiedActivityItems.last {
                        proxy.scrollTo(lastItem.id, anchor: .bottom)
                    }
                }
                .onChange(of: unifiedActivityItems.last?.id) { _, newId in
                    if let id = newId {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }

            if showIndicator {
                WorkingIndicatorView(state: state)
                    .padding(.top, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Waiting for activity")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)
            Text("Send a message in Claude Code to start tracking")
                .font(.system(size: 12))
                .foregroundColor(TerminalColors.dimmedText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PanelHeaderButton: View {
    let sfSymbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: sfSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(isHovered ? TerminalColors.hoverBackground : TerminalColors.subtleBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
