import Foundation
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "StateMachine")

@MainActor
@Observable
final class NotchiStateMachine {
    static let shared = NotchiStateMachine()

    let sessionStore = SessionStore.shared

    private var sleepTimer: Task<Void, Never>?
    private var pendingSyncTasks: [String: Task<Void, Never>] = [:]

    private static let sleepDelay: Duration = .seconds(300)
    private static let syncDebounce: Duration = .milliseconds(100)

    var currentState: NotchiState {
        sessionStore.effectiveSession?.state ?? .idle
    }

    private init() {
        startSleepTimer()
    }

    func handleEvent(_ event: HookEvent) {
        cancelSleepTimer()

        let session = sessionStore.process(event)
        let isDone = event.status == "waiting_for_input"

        switch event.event {
        case "UserPromptSubmit":
            break

        case "PreToolUse":
            if isDone {
                SoundService.shared.playNotificationSound()
            }

        case "PermissionRequest":
            SoundService.shared.playNotificationSound()

        case "PostToolUse":
            scheduleFileSync(sessionId: event.sessionId, cwd: event.cwd)

        case "Stop":
            SoundService.shared.playNotificationSound()
            scheduleFileSync(sessionId: event.sessionId, cwd: event.cwd)

        case "SessionEnd":
            if sessionStore.activeSessionCount == 0 {
                transitionGlobal(to: .idle)
            }

        default:
            if isDone && session.state != .idle {
                SoundService.shared.playNotificationSound()
            }
        }

        startSleepTimer()
    }

    private func transitionGlobal(to newState: NotchiState) {
        logger.info("Global state: \(newState.task.rawValue, privacy: .public)")
    }

    private func startSleepTimer() {
        sleepTimer = Task {
            try? await Task.sleep(for: Self.sleepDelay)
            guard !Task.isCancelled else { return }

            for session in sessionStore.sessions.values {
                session.updateState(.sleeping)
            }
        }
    }

    private func cancelSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = nil
    }

    private func scheduleFileSync(sessionId: String, cwd: String) {
        pendingSyncTasks[sessionId]?.cancel()
        pendingSyncTasks[sessionId] = Task {
            try? await Task.sleep(for: Self.syncDebounce)
            guard !Task.isCancelled else { return }

            let session = sessionStore.sessions[sessionId]
            let messages = await ConversationParser.shared.parseIncremental(
                sessionId: sessionId,
                cwd: cwd,
                after: session?.promptSubmitTime
            )

            if !messages.isEmpty {
                sessionStore.recordAssistantMessages(messages, for: sessionId)
            }

            pendingSyncTasks.removeValue(forKey: sessionId)
        }
    }
}
