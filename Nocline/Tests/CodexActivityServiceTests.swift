import Foundation
import XCTest
@testable import Nocline

final class CodexActivityServiceTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexActivityServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
    }

    func testParseTokenCountLineReadsLastTokenUsage() throws {
        let calendar = makeCalendar()
        let line = tokenCountLine(
            timestamp: "2026-04-26T04:30:00Z",
            lastUsage: usageJSON(input: 1_200, cached: 300, output: 80, reasoning: 20, total: 1_300),
            totalUsage: usageJSON(input: 2_400, cached: 600, output: 160, reasoning: 40, total: 2_600)
        )

        let event = try XCTUnwrap(CodexActivityService.parseTokenCountLine(line, calendar: calendar))

        XCTAssertEqual(event.day, makeDate(year: 2026, month: 4, day: 26, hour: 0, calendar: calendar))
        XCTAssertEqual(event.lastUsage?.inputTokens, 1_200)
        XCTAssertEqual(event.lastUsage?.cachedInputTokens, 300)
        XCTAssertEqual(event.lastUsage?.outputTokens, 80)
        XCTAssertEqual(event.lastUsage?.reasoningOutputTokens, 20)
        XCTAssertEqual(event.lastUsage?.totalTokens, 1_300)
    }

    func testLoadSnapshotAggregatesSameDayAcrossFilesAndEvents() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)
        try writeSessionFile(
            "2026/04/26/one.jsonl",
            lines: [
                tokenCountLine(
                    timestamp: "2026-04-26T01:00:00Z",
                    lastUsage: usageJSON(input: 1_000, cached: 100, output: 100, reasoning: 10, total: 1_100)
                ),
                tokenCountLine(
                    timestamp: "2026-04-26T02:00:00Z",
                    lastUsage: usageJSON(input: 2_000, cached: 200, output: 200, reasoning: 20, total: 2_200)
                ),
            ]
        )
        try writeSessionFile(
            "2026/04/26/two.jsonl",
            lines: [
                tokenCountLine(
                    timestamp: "2026-04-26T03:00:00Z",
                    lastUsage: usageJSON(input: 3_000, cached: 300, output: 300, reasoning: 30, total: 3_300)
                ),
            ]
        )

        let snapshot = try await CodexActivityService.loadSnapshot(
            sessionsRootURL: tempDirectoryURL,
            now: now,
            calendar: calendar,
            fileManager: .default,
            readString: { try String(contentsOf: $0, encoding: .utf8) }
        )
        let targetDay = calendar.startOfDay(for: now)
        let day = try XCTUnwrap(snapshot.days.first { $0.date == targetDay })

        XCTAssertEqual(day.inputTokens, 6_000)
        XCTAssertEqual(day.cachedInputTokens, 600)
        XCTAssertEqual(day.outputTokens, 600)
        XCTAssertEqual(day.reasoningOutputTokens, 60)
        XCTAssertEqual(day.totalTokens, 6_600)
    }

    func testTimestampUsesLocalCalendarDay() async throws {
        let calendar = makeCalendar(timeZone: TimeZone(secondsFromGMT: 8 * 3_600)!)
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)
        let line = tokenCountLine(
            timestamp: "2026-04-25T23:30:00-07:00",
            lastUsage: usageJSON(input: 900, cached: 0, output: 100, reasoning: 0, total: 1_000)
        )
        try writeSessionFile("2026/04/26/timezone.jsonl", lines: [line])

        let snapshot = try await CodexActivityService.loadSnapshot(
            sessionsRootURL: tempDirectoryURL,
            now: now,
            calendar: calendar,
            fileManager: .default,
            readString: { try String(contentsOf: $0, encoding: .utf8) }
        )
        let localDay = makeDate(year: 2026, month: 4, day: 26, hour: 0, calendar: calendar)
        let day = try XCTUnwrap(snapshot.days.first { $0.date == localDay })

        XCTAssertEqual(day.totalTokens, 1_000)
    }

    func testLoadSnapshotReadsOnlyVisibleDayDirectories() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)
        try writeSessionFile(
            "2026/04/26/current.jsonl",
            lines: [
                tokenCountLine(
                    timestamp: "2026-04-26T01:00:00Z",
                    lastUsage: usageJSON(input: 800, cached: 100, output: 200, reasoning: 0, total: 1_000)
                ),
            ]
        )
        try writeSessionFile(
            "2026/01/01/old.jsonl",
            lines: [
                tokenCountLine(
                    timestamp: "2026-01-01T01:00:00Z",
                    lastUsage: usageJSON(input: 8_000, cached: 1_000, output: 2_000, reasoning: 0, total: 10_000)
                ),
            ]
        )

        var readPaths: [String] = []
        let snapshot = try await CodexActivityService.loadSnapshot(
            sessionsRootURL: tempDirectoryURL,
            now: now,
            endDate: now,
            dayCount: 7,
            calendar: calendar,
            fileManager: .default,
            readString: { url in
                readPaths.append(url.path)
                return try String(contentsOf: url, encoding: .utf8)
            }
        )

        XCTAssertEqual(readPaths.count, 1)
        XCTAssertTrue(readPaths.first?.hasSuffix("current.jsonl") == true)
        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertEqual(snapshot.days.reduce(0) { $0 + $1.totalTokens }, 1_000)
    }

    func testDefaultSnapshotCoversLast365Days() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)

        let snapshot = try await CodexActivityService.loadSnapshot(
            sessionsRootURL: tempDirectoryURL,
            now: now,
            calendar: calendar,
            fileManager: .default,
            readString: { try String(contentsOf: $0, encoding: .utf8) }
        )

        let endDate = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -364, to: endDate)

        XCTAssertEqual(snapshot.days.count, 365)
        XCTAssertEqual(snapshot.days.first?.date, startDate)
        XCTAssertEqual(snapshot.days.last?.date, endDate)
    }

    func testSilentRefreshKeepsLoadedSnapshotWhenReloadFails() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)
        let reader = ControlledTokenLineReader()
        try writeSessionFile(
            "2026/04/26/current.jsonl",
            lines: [
                tokenCountLine(
                    timestamp: "2026-04-26T01:00:00Z",
                    lastUsage: usageJSON(input: 800, cached: 100, output: 200, reasoning: 0, total: 1_000),
                    totalUsage: usageJSON(input: 800, cached: 100, output: 200, reasoning: 0, total: 1_000)
                ),
            ]
        )
        let service = CodexActivityService(
            dependencies: CodexActivityServiceDependencies(
                sessionsRootURL: { self.tempDirectoryURL },
                now: { now },
                calendar: { calendar },
                fileManager: .default,
                readString: { try String(contentsOf: $0, encoding: .utf8) },
                readLatestTokenCountLine: { try reader.read($0) }
            )
        )

        await service.refresh()
        let firstSnapshot = try loadedSnapshot(from: service.state)
        reader.shouldFail = true
        try appendToSessionFile("2026/04/26/current.jsonl", line: #"{"timestamp":"2026-04-26T02:00:00Z","type":"response_item","payload":{"text":"changed"}}"#)

        await service.refresh(showsLoading: false)
        let preservedSnapshot = try loadedSnapshot(from: service.state)

        XCTAssertEqual(preservedSnapshot, firstSnapshot)
        XCTAssertEqual(preservedSnapshot.days.reduce(0) { $0 + $1.totalTokens }, 1_000)
    }

    func testLoadSnapshotCanUseLatestTokenCountReaderWithoutReadingWholeFile() async throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)
        try writeSessionFile(
            "2026/04/26/current.jsonl",
            lines: [
                tokenCountLine(
                    timestamp: "2026-04-26T01:00:00Z",
                    lastUsage: usageJSON(input: 800, cached: 100, output: 200, reasoning: 0, total: 1_000),
                    totalUsage: usageJSON(input: 800, cached: 100, output: 200, reasoning: 0, total: 1_000)
                ),
                tokenCountLine(
                    timestamp: "2026-04-26T02:00:00Z",
                    lastUsage: usageJSON(input: 1_600, cached: 200, output: 400, reasoning: 0, total: 2_000),
                    totalUsage: usageJSON(input: 2_400, cached: 300, output: 600, reasoning: 0, total: 3_000)
                ),
            ]
        )

        let snapshot = try await CodexActivityService.loadSnapshot(
            sessionsRootURL: tempDirectoryURL,
            now: now,
            endDate: now,
            dayCount: 7,
            calendar: calendar,
            fileManager: .default,
            readString: { _ in
                XCTFail("Optimized path should not read full file contents")
                return ""
            },
            readLatestTokenCountLine: { url in
                try CodexActivityService.readLatestTokenCountLine(from: url)
            }
        )

        XCTAssertEqual(snapshot.days.reduce(0) { $0 + $1.totalTokens }, 3_000)
    }

    func testReadLatestTokenCountLineScansFromTail() throws {
        let tokenLine = tokenCountLine(
            timestamp: "2026-04-26T02:00:00Z",
            lastUsage: usageJSON(input: 1_600, cached: 200, output: 400, reasoning: 0, total: 2_000),
            totalUsage: usageJSON(input: 2_400, cached: 300, output: 600, reasoning: 0, total: 3_000)
        )
        try writeSessionFile(
            "2026/04/26/large.jsonl",
            lines: [
                #"{"timestamp":"2026-04-26T01:00:00Z","type":"response_item","payload":{"text":"\#(String(repeating: "x", count: 80_000))"}}"#,
                tokenLine,
                #"{"timestamp":"2026-04-26T02:00:01Z","type":"response_item","payload":{"text":"\#(String(repeating: "y", count: 140_000))"}}"#,
            ]
        )
        let url = tempDirectoryURL.appendingPathComponent("2026/04/26/large.jsonl")

        let line = try CodexActivityService.readLatestTokenCountLine(from: url)

        XCTAssertEqual(line, tokenLine)
    }

    func testParseSessionFileFallsBackToMaximumTotalUsageWhenLastUsageIsMissing() throws {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 18, calendar: calendar)
        let startDate = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))!
        let content = [
            tokenCountLine(
                timestamp: "2026-04-26T01:00:00Z",
                lastUsage: nil,
                totalUsage: usageJSON(input: 1_000, cached: 50, output: 100, reasoning: 10, total: 1_100)
            ),
            tokenCountLine(
                timestamp: "2026-04-26T02:00:00Z",
                lastUsage: nil,
                totalUsage: usageJSON(input: 3_000, cached: 150, output: 300, reasoning: 30, total: 3_300)
            ),
        ].joined(separator: "\n")

        let usageByDay = CodexActivityService.parseSessionFile(
            content,
            calendar: calendar,
            startDate: startDate,
            endDate: calendar.startOfDay(for: now)
        )
        let usage = try XCTUnwrap(usageByDay[calendar.startOfDay(for: now)])

        XCTAssertEqual(usage.inputTokens, 3_000)
        XCTAssertEqual(usage.cachedInputTokens, 150)
        XCTAssertEqual(usage.outputTokens, 300)
        XCTAssertEqual(usage.reasoningOutputTokens, 30)
        XCTAssertEqual(usage.totalTokens, 3_300)
    }

    func testFormatTokensUsesDecimalAndCompactUnits() {
        XCTAssertEqual(CodexActivityPresentation.formatTokens(0), "0")
        XCTAssertEqual(CodexActivityPresentation.formatTokens(1_234), "1,234")
        XCTAssertEqual(CodexActivityPresentation.formatTokens(12_400), "12.4K")
        XCTAssertEqual(CodexActivityPresentation.formatTokens(3_200_000), "3.2M")
    }

    private func writeSessionFile(_ relativePath: String, lines: [String]) throws {
        let url = tempDirectoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendToSessionFile(_ relativePath: String, line: String) throws {
        let url = tempDirectoryURL.appendingPathComponent(relativePath)
        let content = try String(contentsOf: url, encoding: .utf8)
        try (content + "\n" + line).write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadedSnapshot(from state: CodexActivityState) throws -> CodexActivitySnapshot {
        guard case .loaded(let snapshot) = state else {
            XCTFail("Expected loaded activity state")
            throw NSError(domain: "CodexActivityServiceTests", code: 2)
        }
        return snapshot
    }

    private func tokenCountLine(timestamp: String, lastUsage: String?, totalUsage: String? = nil) -> String {
        let info: String
        if lastUsage == nil, totalUsage == nil {
            info = "null"
        } else {
            let total = totalUsage ?? lastUsage ?? usageJSON(input: 0, cached: 0, output: 0, reasoning: 0, total: 0)
            let last = lastUsage.map { #","last_token_usage": \#($0)"# } ?? ""
            info = #"{"total_token_usage": \#(total)\#(last),"model_context_window":258400}"#
        }

        return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":\#(info),"rate_limits":{}}}"#
    }

    private func usageJSON(input: Int, cached: Int, output: Int, reasoning: Int, total: Int) -> String {
        """
        {"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)}
        """
    }

    private func makeCalendar(timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}

private final class ControlledTokenLineReader: @unchecked Sendable {
    var shouldFail = false

    func read(_ url: URL) throws -> String? {
        if shouldFail {
            throw NSError(domain: "CodexActivityServiceTests", code: 1)
        }
        return try CodexActivityService.readLatestTokenCountLine(from: url)
    }
}
