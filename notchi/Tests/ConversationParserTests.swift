import Foundation
import XCTest
@testable import notchi

final class ConversationParserTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchi-conversation-parser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        ConversationParser.codexSessionsRootPath = tempDirectoryURL.path
    }

    override func tearDown() async throws {
        ConversationParser.codexSessionsRootPath = ConversationParser.defaultCodexSessionsRootPath
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        try await super.tearDown()
    }

    func testResolvedTranscriptPathUsesExplicitTranscriptPathWhenPresent() {
        let path = ConversationParser.resolvedTranscriptPath(
            sessionId: "session-123",
            cwd: "/tmp/notchi",
            transcriptPath: "/tmp/custom.jsonl"
        )

        XCTAssertEqual(path, "/tmp/custom.jsonl")
    }

    func testResolvedTranscriptPathFallsBackToDerivedSessionPathWhenMissingOrEmpty() {
        ConversationParser.codexSessionsRootPath = "/tmp/codex-sessions"

        let missing = ConversationParser.resolvedTranscriptPath(
            sessionId: "session-123",
            cwd: "/tmp/notchi",
            transcriptPath: nil
        )
        let empty = ConversationParser.resolvedTranscriptPath(
            sessionId: "session-123",
            cwd: "/tmp/notchi",
            transcriptPath: "   "
        )

        XCTAssertEqual(missing, "/tmp/codex-sessions/session-123.jsonl")
        XCTAssertEqual(empty, "/tmp/codex-sessions/session-123.jsonl")
    }

    func testParseIncrementalReadsCodexAssistantResponseItems() async throws {
        let sessionId = "codex-\(UUID().uuidString)"
        let transcriptPath = tempDirectoryURL.appendingPathComponent("rollout-\(sessionId).jsonl").path
        let parser = ConversationParser.shared

        let first = codexAssistantLine(text: "Codex reply", messageId: "msg-1")
        try (first + "\n").write(toFile: transcriptPath, atomically: true, encoding: .utf8)

        let result = await parser.parseIncremental(
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )
        let duplicate = await parser.parseIncremental(
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )

        XCTAssertEqual(result.messages.map(\.text), ["Codex reply"])
        XCTAssertEqual(result.messages.map(\.id), ["msg-1"])
        XCTAssertTrue(duplicate.messages.isEmpty)
    }

    func testParseIncrementalUsesStableCodexOffsetIdsAndHandlesTruncation() async throws {
        let sessionId = "codex-offset-\(UUID().uuidString)"
        let transcriptPath = tempDirectoryURL.appendingPathComponent("rollout-\(sessionId).jsonl").path
        let parser = ConversationParser.shared

        let first = codexAssistantLine(text: "First reply", messageId: nil)
        FileManager.default.createFile(atPath: transcriptPath, contents: Data((first + "\n").utf8))

        let firstResult = await parser.parseIncremental(
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )
        XCTAssertEqual(firstResult.messages.first?.id, "codex-0")

        let second = codexAssistantLine(text: "A", messageId: nil)
        try (second + "\n").write(toFile: transcriptPath, atomically: true, encoding: .utf8)

        let secondResult = await parser.parseIncremental(
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )

        XCTAssertEqual(secondResult.messages.map(\.text), ["A"])
        XCTAssertEqual(secondResult.messages.first?.id, "codex-0")
    }

    func testResolvedTranscriptPathFindsCodexRolloutFallback() throws {
        let sessionId = "session-\(UUID().uuidString)"
        let nestedDirectory = tempDirectoryURL
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("24", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let rolloutPath = nestedDirectory.appendingPathComponent("rollout-\(sessionId).jsonl")
        FileManager.default.createFile(atPath: rolloutPath.path, contents: Data())

        let resolvedPath = ConversationParser.resolvedTranscriptPath(
            sessionId: sessionId,
            cwd: "/tmp/notchi",
            transcriptPath: nil
        )

        XCTAssertEqual(
            URL(fileURLWithPath: resolvedPath).standardizedFileURL.path,
            rolloutPath.standardizedFileURL.path
        )
    }

    private func codexAssistantLine(text: String, messageId: String?) -> String {
        let idField = messageId.map { "\"id\":\"\($0)\"," } ?? ""
        return """
        {"timestamp":"2026-04-24T09:50:04.954Z","type":"response_item","payload":{\(idField)"type":"message","role":"assistant","content":[{"type":"output_text","text":"\(text)"}]}}
        """
    }
}
