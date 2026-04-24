import Foundation

enum AgentProvider: String, Codable, Sendable, CaseIterable {
    case codex

    var displayName: String {
        "Codex CLI"
    }

    var shortName: String {
        "Codex"
    }
}
