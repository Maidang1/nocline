//
//  ConversationParser.swift
//  notchi
//
//  Parses CLI JSONL conversation files to extract assistant text messages.
//  Uses incremental parsing to only read new lines since last sync.
//

import Foundation

struct ParseResult {
    let messages: [AssistantMessage]
    let interrupted: Bool
}

actor ConversationParser {
    static let shared = ConversationParser()
    static let defaultCodexSessionsRootPath = "\(NSHomeDirectory())/.codex/sessions"
    static var codexSessionsRootPath = defaultCodexSessionsRootPath

    private var lastFileOffset: [String: UInt64] = [:]
    private var seenMessageIds: [String: Set<String>] = [:]

    private static let emptyResult = ParseResult(messages: [], interrupted: false)

    @MainActor
    static func configureCodexSessionsRootPath(using codexConfig: CodexConfigDirectoryResolution) {
        codexSessionsRootPath = codexConfig.sessionsDirectoryURL.path
    }

    static func resolvedTranscriptPath(
        sessionId: String,
        cwd: String,
        transcriptPath: String?
    ) -> String {
        if let trimmedPath = transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedPath.isEmpty {
            return trimmedPath
        }

        return derivedCodexTranscriptPath(sessionId: sessionId)
    }

    /// Parse only NEW assistant text messages since last call
    func parseIncremental(
        sessionId: String,
        transcriptPath: String
    ) -> ParseResult {
        guard FileManager.default.fileExists(atPath: transcriptPath) else {
            return Self.emptyResult
        }

        guard let fileHandle = FileHandle(forReadingAtPath: transcriptPath) else {
            return Self.emptyResult
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64
        do {
            fileSize = try fileHandle.seekToEnd()
        } catch {
            return Self.emptyResult
        }

        let parserKey = Self.parserKey(sessionId: sessionId)
        var currentOffset = lastFileOffset[parserKey] ?? 0

        if fileSize < currentOffset {
            currentOffset = 0
            seenMessageIds[parserKey] = []
        }

        if fileSize == currentOffset {
            return Self.emptyResult
        }

        do {
            try fileHandle.seek(toOffset: currentOffset)
        } catch {
            return Self.emptyResult
        }

        guard let newData = try? fileHandle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return Self.emptyResult
        }

        var messages: [AssistantMessage] = []
        var seen = seenMessageIds[parserKey] ?? []
        var lineStartOffset = currentOffset
        let lines = newContent.components(separatedBy: "\n")

        for line in lines {
            defer {
                let byteCount = line.data(using: .utf8)?.count ?? 0
                lineStartOffset += UInt64(byteCount + 1)
            }
            guard !line.isEmpty else { continue }

            guard let message = Self.parseCodexLine(line, fallbackOffset: lineStartOffset) else { continue }
            guard seen.insert(message.id).inserted else { continue }
            messages.append(message)
        }

        lastFileOffset[parserKey] = fileSize
        seenMessageIds[parserKey] = seen

        return ParseResult(messages: messages, interrupted: false)
    }

    /// Reset parsing state for a session
    func resetState(for sessionId: String) {
        let key = Self.parserKey(sessionId: sessionId)
        lastFileOffset.removeValue(forKey: key)
        seenMessageIds.removeValue(forKey: key)
    }

    /// Mark current file position as "already processed"
    /// Call this when a new prompt is submitted to ignore previous content
    func markCurrentPosition(
        sessionId: String,
        transcriptPath: String
    ) {
        let parserKey = Self.parserKey(sessionId: sessionId)
        guard let fileHandle = FileHandle(forReadingAtPath: transcriptPath) else {
            lastFileOffset[parserKey] = 0
            seenMessageIds[parserKey] = []
            return
        }
        defer { try? fileHandle.close() }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        lastFileOffset[parserKey] = fileSize
        seenMessageIds[parserKey] = []
    }

    private static func parserKey(sessionId: String) -> String {
        sessionId
    }
    private static func derivedCodexTranscriptPath(sessionId: String) -> String {
        let directPath = "\(codexSessionsRootPath)/\(sessionId).jsonl"
        if FileManager.default.fileExists(atPath: directPath) {
            return directPath
        }

        let rootURL = URL(fileURLWithPath: codexSessionsRootPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return directPath
        }

        var bestURL: URL?
        var bestDate = Date.distantPast
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  fileURL.lastPathComponent.contains(sessionId) else {
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modificationDate = values?.contentModificationDate ?? Date.distantPast
            if modificationDate > bestDate {
                bestDate = modificationDate
                bestURL = fileURL
            }
        }

        return bestURL?.path ?? directPath
    }

    private static func parseCodexLine(_ line: String, fallbackOffset: UInt64) -> AssistantMessage? {
        guard let lineData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let type = json["type"] as? String,
              type == "response_item",
              let payload = json["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "message",
              let role = payload["role"] as? String,
              role == "assistant",
              let contentArray = payload["content"] as? [[String: Any]] else {
            return nil
        }

        let textParts = contentArray.compactMap { block -> String? in
            guard let blockType = block["type"] as? String,
                  blockType == "output_text",
                  let text = block["text"] as? String else {
                return nil
            }
            return text
        }

        let fullText = textParts.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else { return nil }

        let id = (payload["id"] as? String) ?? "codex-\(fallbackOffset)"
        return AssistantMessage(
            id: id,
            text: fullText,
            timestamp: parseTimestamp(json["timestamp"] as? String)
        )
    }

    private static func parseTimestamp(_ rawValue: String?) -> Date {
        guard let rawValue else { return Date() }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue) ?? Date()
    }
}
