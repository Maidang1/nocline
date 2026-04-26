import Combine
import Foundation

nonisolated struct CodexActivityTokenUsage: Equatable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    nonisolated static var zero: CodexActivityTokenUsage {
        CodexActivityTokenUsage(
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 0
        )
    }

    nonisolated static func + (lhs: CodexActivityTokenUsage, rhs: CodexActivityTokenUsage) -> CodexActivityTokenUsage {
        CodexActivityTokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }
}

nonisolated struct CodexActivityDay: Identifiable, Equatable, Sendable {
    let date: Date
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    var id: Date { date }

    init(date: Date, usage: CodexActivityTokenUsage) {
        self.date = date
        inputTokens = usage.inputTokens
        cachedInputTokens = usage.cachedInputTokens
        outputTokens = usage.outputTokens
        reasoningOutputTokens = usage.reasoningOutputTokens
        totalTokens = usage.totalTokens
    }
}

nonisolated struct CodexActivitySnapshot: Equatable, Sendable {
    let days: [CodexActivityDay]
    let startDate: Date
    let endDate: Date
    let generatedAt: Date
}

enum CodexActivityState: Equatable {
    case idle
    case loading
    case loaded(CodexActivitySnapshot)
    case unavailable
}

nonisolated struct CodexActivityPresentation: Equatable, Sendable {
    let days: [CodexActivityDay]
    let activeDayCount: Int
    let totalTokenText: String
    let todayTokenText: String
    let maxDailyTokens: Int

    static func make(
        from state: CodexActivityState,
        calendar: Calendar = .current,
        now: Date = Date(),
        dayCount: Int = 84
    ) -> Self {
        let days: [CodexActivityDay]
        switch state {
        case .loaded(let snapshot):
            days = snapshot.days
        case .idle, .loading, .unavailable:
            days = Self.emptyDays(calendar: calendar, now: now, dayCount: dayCount)
        }

        let today = calendar.startOfDay(for: now)
        let todayTokens = days.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.totalTokens ?? 0
        let totalTokens = days.reduce(0) { $0 + $1.totalTokens }

        return CodexActivityPresentation(
            days: days,
            activeDayCount: days.filter { $0.totalTokens > 0 }.count,
            totalTokenText: Self.formatTokens(totalTokens),
            todayTokenText: Self.formatTokens(todayTokens),
            maxDailyTokens: days.map(\.totalTokens).max() ?? 0
        )
    }

    static func formatTokens(_ value: Int) -> String {
        if value < 10_000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        if value < 1_000_000 {
            return compact(value, divisor: 1_000, suffix: "K")
        }

        return compact(value, divisor: 1_000_000, suffix: "M")
    }

    private static func compact(_ value: Int, divisor: Double, suffix: String) -> String {
        let scaled = Double(value) / divisor
        if scaled >= 100 || scaled.rounded() == scaled {
            return String(format: "%.0f%@", scaled, suffix)
        }
        return String(format: "%.1f%@", scaled, suffix)
    }

    private static func emptyDays(calendar: Calendar, now: Date, dayCount: Int) -> [CodexActivityDay] {
        let today = calendar.startOfDay(for: now)
        let visibleDayCount = max(1, dayCount)
        let start = calendar.date(byAdding: .day, value: -(visibleDayCount - 1), to: today) ?? today

        return (0..<visibleDayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return CodexActivityDay(date: date, usage: .zero)
        }
    }
}

nonisolated private struct CodexActivityLoadResult: Sendable {
    let snapshot: CodexActivitySnapshot
    let fileSummaryCache: [String: CodexActivityFileCacheEntry]
}

nonisolated private struct CodexActivityFileProcessingResult: Sendable {
    let path: String
    let cacheEntry: CodexActivityFileCacheEntry?
    let usageByDay: [Date: CodexActivityTokenUsage]
}

nonisolated private struct CodexActivityFileCacheEntry: Equatable, Sendable {
    let identity: CodexActivityFileIdentity
    let usageByDay: [Date: CodexActivityTokenUsage]
}

nonisolated private struct CodexActivityFileIdentity: Equatable, Sendable {
    let size: UInt64
    let modificationTime: TimeInterval
}

struct CodexActivityServiceDependencies {
    var sessionsRootURL: @Sendable () -> URL
    var now: @Sendable () -> Date
    var calendar: @Sendable () -> Calendar
    var fileManager: FileManager
    var readString: @Sendable (URL) throws -> String
    var readLatestTokenCountLine: @Sendable (URL) throws -> String?

    static let live = CodexActivityServiceDependencies(
        sessionsRootURL: {
            URL(fileURLWithPath: ConversationParser.codexSessionsRootPath, isDirectory: true)
        },
        now: { Date() },
        calendar: { .current },
        fileManager: .default,
        readString: { url in
            try String(contentsOf: url, encoding: .utf8)
        },
        readLatestTokenCountLine: { url in
            try CodexActivityService.readLatestTokenCountLine(from: url)
        }
    )
}

@MainActor
final class CodexActivityService: ObservableObject {
    static let shared = CodexActivityService(dependencies: .live)
    nonisolated static let defaultVisibleDayCount = 365
    nonisolated private static let fileReadConcurrency = 8

    @Published private(set) var state: CodexActivityState = .idle

    private let dependencies: CodexActivityServiceDependencies
    private var hasRefreshedOnce = false
    private var fileSummaryCache: [String: CodexActivityFileCacheEntry] = [:]
    private var activeRefreshTask: Task<CodexActivityLoadResult, Error>?

    init(dependencies: CodexActivityServiceDependencies) {
        self.dependencies = dependencies
    }

    func refreshIfNeeded() async {
        guard !hasRefreshedOnce else { return }
        hasRefreshedOnce = true
        await refresh()
    }

    func refresh(
        endingAt requestedEndDate: Date? = nil,
        dayCount: Int = defaultVisibleDayCount,
        showsLoading: Bool = true
    ) async {
        let previousState = state
        let preservesLoadedState = !showsLoading && previousState.isLoaded
        if showsLoading || !preservesLoadedState {
            state = .loading
        }

        let refreshTask: Task<CodexActivityLoadResult, Error>
        if let activeRefreshTask {
            refreshTask = activeRefreshTask
        } else {
            refreshTask = makeRefreshTask(endingAt: requestedEndDate, dayCount: dayCount)
            activeRefreshTask = refreshTask
        }

        do {
            let result = try await refreshTask.value
            if activeRefreshTask != nil {
                activeRefreshTask = nil
            }
            fileSummaryCache = result.fileSummaryCache
            state = .loaded(result.snapshot)
        } catch {
            if activeRefreshTask != nil {
                activeRefreshTask = nil
            }
            state = preservesLoadedState ? previousState : .unavailable
        }
    }

    private func makeRefreshTask(
        endingAt requestedEndDate: Date?,
        dayCount: Int
    ) -> Task<CodexActivityLoadResult, Error> {
        let sessionsRootURL = dependencies.sessionsRootURL()
        let now = dependencies.now()
        let calendar = dependencies.calendar()
        let endDate = calendar.startOfDay(for: requestedEndDate ?? now)
        let fileManager = dependencies.fileManager
        let readString = dependencies.readString
        let readLatestTokenCountLine = dependencies.readLatestTokenCountLine
        let cachedFileSummaries = fileSummaryCache

        return Task.detached(priority: .utility) {
            try await Self.loadSnapshotResult(
                sessionsRootURL: sessionsRootURL,
                now: now,
                endDate: endDate,
                dayCount: dayCount,
                calendar: calendar,
                fileManager: fileManager,
                readString: readString,
                readLatestTokenCountLine: readLatestTokenCountLine,
                fileSummaryCache: cachedFileSummaries
            )
        }
    }
}

private extension CodexActivityState {
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

extension CodexActivityService {
    nonisolated static func loadSnapshot(
        sessionsRootURL: URL,
        now: Date,
        endDate: Date? = nil,
        dayCount: Int = defaultVisibleDayCount,
        calendar: Calendar,
        fileManager: FileManager,
        readString: @escaping @Sendable (URL) throws -> String,
        readLatestTokenCountLine: (@Sendable (URL) throws -> String?)? = nil
    ) async throws -> CodexActivitySnapshot {
        try await loadSnapshotResult(
            sessionsRootURL: sessionsRootURL,
            now: now,
            endDate: endDate,
            dayCount: dayCount,
            calendar: calendar,
            fileManager: fileManager,
            readString: readString,
            readLatestTokenCountLine: readLatestTokenCountLine,
            fileSummaryCache: [:]
        ).snapshot
    }

    nonisolated private static func loadSnapshotResult(
        sessionsRootURL: URL,
        now: Date,
        endDate: Date? = nil,
        dayCount: Int = defaultVisibleDayCount,
        calendar: Calendar,
        fileManager: FileManager,
        readString: @escaping @Sendable (URL) throws -> String,
        readLatestTokenCountLine: (@Sendable (URL) throws -> String?)? = nil,
        fileSummaryCache: [String: CodexActivityFileCacheEntry]
    ) async throws -> CodexActivityLoadResult {
        let visibleEndDate = calendar.startOfDay(for: endDate ?? now)
        let visibleDayCount = max(1, dayCount)
        let startDate = calendar.date(byAdding: .day, value: -(visibleDayCount - 1), to: visibleEndDate) ?? visibleEndDate
        let files = try sessionFiles(
            in: sessionsRootURL,
            startDate: startDate,
            endDate: visibleEndDate,
            calendar: calendar,
            fileManager: fileManager
        )
        var usageByDay: [Date: CodexActivityTokenUsage] = [:]
        var updatedFileSummaryCache = fileSummaryCache

        if let readLatestTokenCountLine {
            let fileResults = try await parseSessionFileSummaries(
                files,
                calendar: calendar,
                readLatestTokenCountLine: readLatestTokenCountLine,
                fileSummaryCache: fileSummaryCache
            )

            for result in fileResults {
                if let cacheEntry = result.cacheEntry {
                    updatedFileSummaryCache[result.path] = cacheEntry
                }
                merge(result.usageByDay, into: &usageByDay, startDate: startDate, endDate: visibleEndDate)
            }
        } else {
            for fileURL in files {
                let content = try readString(fileURL)
                let fileUsage = parseSessionFile(
                    content,
                    calendar: calendar,
                    startDate: startDate,
                    endDate: visibleEndDate
                )
                merge(fileUsage, into: &usageByDay, startDate: startDate, endDate: visibleEndDate)
            }
        }

        let days = (0..<visibleDayCount).map { offset -> CodexActivityDay in
            let date = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            return CodexActivityDay(date: date, usage: usageByDay[date] ?? .zero)
        }

        let snapshot = CodexActivitySnapshot(
            days: days,
            startDate: startDate,
            endDate: visibleEndDate,
            generatedAt: now
        )

        return CodexActivityLoadResult(snapshot: snapshot, fileSummaryCache: updatedFileSummaryCache)
    }

    nonisolated static func parseSessionFileSummary(
        _ fileURL: URL,
        calendar: Calendar,
        readLatestTokenCountLine: @Sendable (URL) throws -> String?
    ) throws -> [Date: CodexActivityTokenUsage] {
        guard let line = try readLatestTokenCountLine(fileURL),
              let event = parseTokenCountLine(line, calendar: calendar) else {
            return [:]
        }

        guard let usage = event.totalUsage ?? event.lastUsage else {
            return [:]
        }

        return [event.day: usage]
    }

    nonisolated static func parseSessionFile(
        _ content: String,
        calendar: Calendar,
        startDate: Date,
        endDate: Date
    ) -> [Date: CodexActivityTokenUsage] {
        var usageByDay: [Date: CodexActivityTokenUsage] = [:]
        var hasLastUsage = false
        var fallback: (day: Date, usage: CodexActivityTokenUsage)?

        for line in content.split(whereSeparator: \.isNewline) {
            guard let event = parseTokenCountLine(String(line), calendar: calendar) else { continue }
            guard event.day >= startDate, event.day <= endDate else { continue }

            if let lastUsage = event.lastUsage {
                hasLastUsage = true
                usageByDay[event.day, default: .zero] = usageByDay[event.day, default: .zero] + lastUsage
            } else if let totalUsage = event.totalUsage,
                      fallback == nil || totalUsage.totalTokens > fallback!.usage.totalTokens {
                fallback = (event.day, totalUsage)
            }
        }

        if !hasLastUsage, let fallback {
            usageByDay[fallback.day, default: .zero] = usageByDay[fallback.day, default: .zero] + fallback.usage
        }

        return usageByDay
    }

    nonisolated static func parseTokenCountLine(
        _ line: String,
        calendar: Calendar
    ) -> CodexActivityTokenCountEvent? {
        guard line.contains(#""token_count""#) else {
            return nil
        }

        guard let data = line.data(using: .utf8),
              let event = try? makeActivityDecoder().decode(CodexActivityJSONLine.self, from: data),
              event.type == "event_msg",
              event.payload.type == "token_count" else {
            return nil
        }

        let day = calendar.startOfDay(for: event.timestamp)
        return CodexActivityTokenCountEvent(
            day: day,
            lastUsage: event.payload.info?.lastTokenUsage?.activityUsage,
            totalUsage: event.payload.info?.totalTokenUsage?.activityUsage
        )
    }

    nonisolated static func readLatestTokenCountLine(from fileURL: URL) throws -> String? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset = try handle.seekToEnd()
        var partialLinePrefix = Data()
        let chunkSize = 64 * 1_024

        while offset > 0 {
            let readSize = min(chunkSize, Int(offset))
            offset -= UInt64(readSize)
            try handle.seek(toOffset: offset)

            var buffer = handle.readData(ofLength: readSize)
            buffer.append(partialLinePrefix)

            let scanStart: Data.Index
            if offset > 0 {
                guard let firstNewline = buffer.firstIndex(of: 0x0A) else {
                    partialLinePrefix = buffer
                    continue
                }
                partialLinePrefix = Data(buffer[..<firstNewline])
                scanStart = buffer.index(after: firstNewline)
            } else {
                partialLinePrefix.removeAll(keepingCapacity: false)
                scanStart = buffer.startIndex
            }

            let scanData = buffer[scanStart..<buffer.endIndex]
            let text = String(decoding: scanData, as: UTF8.self)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if let line = lines.reversed().first(where: { $0.contains(#""token_count""#) }) {
                return String(line)
            }
        }

        return nil
    }

    nonisolated private static func parseSessionFileSummaries(
        _ files: [URL],
        calendar: Calendar,
        readLatestTokenCountLine: @escaping @Sendable (URL) throws -> String?,
        fileSummaryCache: [String: CodexActivityFileCacheEntry]
    ) async throws -> [CodexActivityFileProcessingResult] {
        guard !files.isEmpty else { return [] }

        var iterator = files.makeIterator()
        var results: [CodexActivityFileProcessingResult] = []
        results.reserveCapacity(files.count)

        try await withThrowingTaskGroup(of: CodexActivityFileProcessingResult.self) { group in
            func enqueueNextFile() {
                guard let fileURL = iterator.next() else { return }
                group.addTask {
                    try parseSessionFileSummaryWithCache(
                        fileURL,
                        calendar: calendar,
                        readLatestTokenCountLine: readLatestTokenCountLine,
                        fileSummaryCache: fileSummaryCache
                    )
                }
            }

            for _ in 0..<min(fileReadConcurrency, files.count) {
                enqueueNextFile()
            }

            while let result = try await group.next() {
                results.append(result)
                enqueueNextFile()
            }
        }

        return results
    }

    nonisolated private static func parseSessionFileSummaryWithCache(
        _ fileURL: URL,
        calendar: Calendar,
        readLatestTokenCountLine: @Sendable (URL) throws -> String?,
        fileSummaryCache: [String: CodexActivityFileCacheEntry]
    ) throws -> CodexActivityFileProcessingResult {
        let path = fileURL.path
        let identityBeforeRead = fileIdentity(for: fileURL)
        if let identityBeforeRead,
           let cached = fileSummaryCache[path],
           cached.identity == identityBeforeRead {
            return CodexActivityFileProcessingResult(
                path: path,
                cacheEntry: nil,
                usageByDay: cached.usageByDay
            )
        }

        let usageByDay = try parseSessionFileSummary(
            fileURL,
            calendar: calendar,
            readLatestTokenCountLine: readLatestTokenCountLine
        )
        let identityAfterRead = fileIdentity(for: fileURL)
        let cacheEntry: CodexActivityFileCacheEntry?
        if let identityBeforeRead,
           identityBeforeRead == identityAfterRead {
            cacheEntry = CodexActivityFileCacheEntry(identity: identityBeforeRead, usageByDay: usageByDay)
        } else {
            cacheEntry = nil
        }

        return CodexActivityFileProcessingResult(
            path: path,
            cacheEntry: cacheEntry,
            usageByDay: usageByDay
        )
    }

    nonisolated private static func merge(
        _ fileUsage: [Date: CodexActivityTokenUsage],
        into usageByDay: inout [Date: CodexActivityTokenUsage],
        startDate: Date,
        endDate: Date
    ) {
        for (day, usage) in fileUsage where day >= startDate && day <= endDate {
            usageByDay[day, default: .zero] = usageByDay[day, default: .zero] + usage
        }
    }

    nonisolated private static func fileIdentity(for fileURL: URL) -> CodexActivityFileIdentity? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let fileSize = values.fileSize else {
            return nil
        }

        return CodexActivityFileIdentity(
            size: UInt64(max(0, fileSize)),
            modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    nonisolated private static func sessionFiles(
        in rootURL: URL,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        fileManager: FileManager
    ) throws -> [URL] {
        var files: [URL] = []
        var visitedDirectories: Set<String> = []
        var day = startDate

        while day <= endDate {
            let directoryURL = dayDirectoryURL(rootURL: rootURL, date: day, calendar: calendar)
            if visitedDirectories.insert(directoryURL.path).inserted,
               fileManager.fileExists(atPath: directoryURL.path) {
                files.append(contentsOf: jsonlFiles(in: directoryURL, fileManager: fileManager))
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        files.append(contentsOf: topLevelJSONLFiles(in: rootURL, fileManager: fileManager))
        return files
    }

    nonisolated private static func jsonlFiles(in directoryURL: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            files.append(fileURL)
        }
        return files
    }

    nonisolated private static func topLevelJSONLFiles(in rootURL: URL, fileManager: FileManager) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.filter { $0.pathExtension == "jsonl" }
    }

    nonisolated private static func dayDirectoryURL(rootURL: URL, date: Date, calendar: Calendar) -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)

        return rootURL
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
    }
}

nonisolated struct CodexActivityTokenCountEvent: Equatable, Sendable {
    let day: Date
    let lastUsage: CodexActivityTokenUsage?
    let totalUsage: CodexActivityTokenUsage?
}

nonisolated private func makeActivityDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
    }
    return decoder
}

nonisolated private struct CodexActivityJSONLine: Decodable {
    let timestamp: Date
    let type: String
    let payload: CodexActivityPayload
}

nonisolated private struct CodexActivityPayload: Decodable {
    let type: String
    let info: CodexActivityInfo?
}

nonisolated private struct CodexActivityInfo: Decodable {
    let totalTokenUsage: CodexActivityUsagePayload?
    let lastTokenUsage: CodexActivityUsagePayload?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
    }
}

nonisolated private struct CodexActivityUsagePayload: Decodable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    var activityUsage: CodexActivityTokenUsage {
        CodexActivityTokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            totalTokens: totalTokens
        )
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }
}
