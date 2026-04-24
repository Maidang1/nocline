import XCTest
@testable import notchi

@MainActor
final class SessionStoreTests: XCTestCase {
    override func tearDown() async throws {
        let sessionIds = Array(SessionStore.shared.sessions.keys)
        sessionIds.forEach { SessionStore.shared.dismissSession($0) }
        try await super.tearDown()
    }

    func testUserPromptSubmitClearsPreviousTurnToolEventsAndAssistantMessages() {
        let sessionId = "turn-reset-\(UUID().uuidString)"
        let store = SessionStore.shared

        let session = store.process(makeEvent(
            sessionId: sessionId,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "first"
        ))

        _ = store.process(makeEvent(
            sessionId: sessionId,
            event: "PreToolUse",
            status: "processing",
            tool: "Read",
            toolUseId: "tool-1"
        ))
        session.recordAssistantMessages([
            AssistantMessage(id: UUID().uuidString, text: "Old reply", timestamp: Date())
        ])

        XCTAssertEqual(session.recentEvents.count, 1)
        XCTAssertEqual(session.recentAssistantMessages.count, 1)

        _ = store.process(makeEvent(
            sessionId: sessionId,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "second"
        ))

        XCTAssertTrue(session.recentEvents.isEmpty)
        XCTAssertTrue(session.recentAssistantMessages.isEmpty)
        XCTAssertEqual(session.lastUserPrompt, "second")
    }

    func testDisplaySessionNumbersRenumberAfterDismissal() {
        let store = SessionStore.shared
        let cwd = "/tmp/notchi"

        let first = store.process(makeEvent(
            sessionId: "renumber-1-\(UUID().uuidString)",
            cwd: cwd,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "one"
        ))
        let second = store.process(makeEvent(
            sessionId: "renumber-2-\(UUID().uuidString)",
            cwd: cwd,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "two"
        ))
        let third = store.process(makeEvent(
            sessionId: "renumber-3-\(UUID().uuidString)",
            cwd: cwd,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "three"
        ))

        XCTAssertEqual(store.displaySessionNumber(for: first), 1)
        XCTAssertEqual(store.displaySessionNumber(for: second), 2)
        XCTAssertEqual(store.displaySessionNumber(for: third), 3)

        store.dismissSession(first.id)
        store.dismissSession(second.id)

        XCTAssertEqual(store.displaySessionNumber(for: third), 1)
        XCTAssertEqual(store.displaySessionLabel(for: third), "notchi #1")
        XCTAssertEqual(store.displayTitle(for: third), "notchi #1 - three")
    }

    func testCodexLifecycleTracksProviderAndActiveWorkState() throws {
        let store = SessionStore.shared
        let sessionId = "codex-lifecycle-\(UUID().uuidString)"

        let session = store.process(makeEvent(
            sessionId: sessionId,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "run pwd"
        ))

        XCTAssertEqual(session.provider, .codex)
        XCTAssertEqual(session.task, .working)
        XCTAssertEqual(store.activeWorkSessionCount, 1)

        _ = store.process(makeEvent(
            sessionId: sessionId,
            event: "PreToolUse",
            status: "running_tool",
            tool: "Bash",
            toolInput: try makeToolInput(["command": "pwd"]),
            toolUseId: "tool-1"
        ))

        XCTAssertEqual(session.recentEvents.last?.description, "pwd")

        _ = store.process(makeEvent(
            sessionId: sessionId,
            event: "PermissionRequest",
            status: "waiting_for_input",
            tool: "Bash",
            toolInput: try makeToolInput(["command": "pwd"]),
            toolUseId: "tool-1"
        ))

        XCTAssertEqual(session.task, .waiting)
        XCTAssertEqual(session.pendingQuestions.first?.options.first?.label, "Respond in terminal")

        _ = store.process(makeEvent(
            sessionId: sessionId,
            event: "PostToolUse",
            status: "processing",
            tool: "Bash",
            toolUseId: "tool-1"
        ))
        XCTAssertEqual(session.recentEvents.last?.status, .success)

        _ = store.process(makeEvent(
            sessionId: sessionId,
            event: "Stop",
            status: "waiting_for_input"
        ))

        XCTAssertEqual(session.task, .idle)
        XCTAssertFalse(session.isProcessing)
        XCTAssertEqual(store.activeWorkSessionCount, 0)
        XCTAssertEqual(store.sessions[sessionId]?.provider, .codex)
    }

    func testStaleCodexIdlePruningKeepsActiveCodexSessions() {
        let store = SessionStore.shared
        let codexIdleId = "codex-idle-\(UUID().uuidString)"
        let codexWorkingId = "codex-working-\(UUID().uuidString)"

        _ = store.process(makeEvent(
            sessionId: codexIdleId,
            event: "Stop",
            status: "waiting_for_input"
        ))
        _ = store.process(makeEvent(
            sessionId: codexWorkingId,
            event: "UserPromptSubmit",
            status: "processing",
            userPrompt: "work"
        ))

        store.pruneStaleCodexIdleSessions(maxIdleAge: -1)

        XCTAssertNil(store.sessions[codexIdleId])
        XCTAssertNotNil(store.sessions[codexWorkingId])
    }

    private func makeEvent(
        provider: AgentProvider = .codex,
        sessionId: String,
        cwd: String = "/tmp",
        event: String,
        status: String,
        userPrompt: String? = nil,
        tool: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        toolUseId: String? = nil
    ) -> HookEvent {
        HookEvent(
            provider: provider,
            sessionId: sessionId,
            transcriptPath: nil,
            cwd: cwd,
            event: event,
            status: status,
            pid: nil,
            tty: nil,
            tool: tool,
            toolInput: toolInput,
            toolUseId: toolUseId,
            userPrompt: userPrompt,
            permissionMode: nil,
            interactive: true
        )
    }

    private func makeToolInput(_ dictionary: [String: Any]) throws -> [String: AnyCodable] {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try JSONDecoder().decode([String: AnyCodable].self, from: data)
    }
}
