import Foundation
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "StateMachine")

@MainActor
@Observable
final class NotchiStateMachine {
    static let shared = NotchiStateMachine()

    private(set) var currentState: NotchiState = .idle
    let stats = SessionStats()

    private var sleepTimer: Task<Void, Never>?
    private var pendingSyncTask: Task<Void, Never>?

    private static let sleepDelay: Duration = .seconds(300)
    private static let syncDebounce: Duration = .milliseconds(100)

    private init() {
        startSleepTimer()
    }

    func handleEvent(_ event: HookEvent) {
        cancelSleepTimer()
        stats.updateProcessingState(status: event.status)
        stats.recordSessionInfo(sessionId: event.sessionId, cwd: event.cwd)

        let isDone = event.status == "waiting_for_input"

        switch event.event {
        case "UserPromptSubmit":
            if let prompt = event.userPrompt {
                stats.recordUserPrompt(prompt)
            }
            // Mark current file position so only NEW responses after this prompt are shown
            Task {
                await ConversationParser.shared.markCurrentPosition(
                    sessionId: event.sessionId,
                    cwd: event.cwd
                )
            }
            stats.clearAssistantMessages()
            transition(to: .thinking)

        case "PreCompact":
            transition(to: .compacting)

        case "SessionStart":
            stats.startSession()
            transition(to: .thinking)

        case "PreToolUse":
            let toolInput = event.toolInput?.mapValues { $0.value }
            stats.recordPreToolUse(tool: event.tool, toolInput: toolInput, toolUseId: event.toolUseId)
            transition(to: .thinking)
            if isDone {
                SoundService.shared.playNotificationSound()
            }

        case "PermissionRequest":
            transition(to: .thinking)
            SoundService.shared.playNotificationSound()

        case "PostToolUse":
            let success = event.status != "error"
            stats.recordPostToolUse(tool: event.tool, toolUseId: event.toolUseId, success: success)
            scheduleFileSync(sessionId: event.sessionId, cwd: event.cwd)

        case "Stop":
            transition(to: .happy)
            SoundService.shared.playNotificationSound()
            scheduleFileSync(sessionId: event.sessionId, cwd: event.cwd)

        case "SubagentStop":
            transition(to: .happy)

        case "SessionEnd":
            stats.endSession()
            transition(to: .idle)

        default:
            if isDone && currentState != .idle {
                transition(to: .happy)
                SoundService.shared.playNotificationSound()
            }
        }

        startSleepTimer()
    }

    private func transition(to newState: NotchiState) {
        guard currentState != newState else { return }
        logger.info("State: \(self.currentState.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public)")
        currentState = newState
    }

    private func startSleepTimer() {
        sleepTimer = Task {
            try? await Task.sleep(for: Self.sleepDelay)
            guard !Task.isCancelled else { return }
            transition(to: .sleeping)
        }
    }

    private func cancelSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = nil
    }

    private func scheduleFileSync(sessionId: String, cwd: String) {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task {
            try? await Task.sleep(for: Self.syncDebounce)
            guard !Task.isCancelled else { return }

            let messages = await ConversationParser.shared.parseIncremental(
                sessionId: sessionId,
                cwd: cwd
            )

            // Only record if session is still current
            if !messages.isEmpty && stats.currentSessionId == sessionId {
                stats.recordAssistantMessages(messages)
            }
        }
    }
}
