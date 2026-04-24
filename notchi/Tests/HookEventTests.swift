import Foundation
import XCTest
@testable import notchi

final class HookEventTests: XCTestCase {
    func testPayloadRequiresExplicitProvider() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "session_id": "codex-session",
            "transcript_path": "/tmp/codex.jsonl",
            "cwd": "/tmp",
            "event": "SessionStart",
            "status": "waiting_for_input",
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(HookEvent.self, from: data))
    }

    func testCodexPayloadDecodesProviderAwareFields() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "provider": "codex",
            "session_id": "codex-session",
            "turn_id": "turn-1",
            "transcript_path": "/tmp/codex.jsonl",
            "cwd": "/tmp",
            "event": "PreToolUse",
            "status": "running_tool",
            "tool": "Bash",
            "tool_use_id": "tool-1",
            "tool_input": ["command": "pwd"],
            "permission_mode": "default",
            "model": "gpt-5.5",
            "source": "codex-cli",
            "interactive": true,
        ])

        let event = try JSONDecoder().decode(HookEvent.self, from: data)

        XCTAssertEqual(event.provider, .codex)
        XCTAssertEqual(event.turnId, "turn-1")
        XCTAssertEqual(event.model, "gpt-5.5")
        XCTAssertEqual(event.source, "codex-cli")
        XCTAssertEqual(event.tool, "Bash")
        XCTAssertEqual(event.toolInput?["command"]?.value as? String, "pwd")
    }

    func testHookEventAllowsMissingOptionalFields() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "provider": "codex",
            "session_id": "minimal",
            "event": "Stop",
            "status": "waiting_for_input",
        ])

        let event = try JSONDecoder().decode(HookEvent.self, from: data)

        XCTAssertEqual(event.provider, .codex)
        XCTAssertEqual(event.cwd, "")
        XCTAssertNil(event.transcriptPath)
    }
}
