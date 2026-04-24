import Combine
import Foundation

struct CodexAuthSnapshot: Equatable {
    let accessToken: String
    let accountId: String
}

struct CodexUsageWindow: Equatable {
    let remainingPercent: Int
    let usedPercent: Int
    let resetAt: Date
}

struct CodexUsageSnapshot: Equatable {
    let fiveHour: CodexUsageWindow
    let week: CodexUsageWindow
    let planType: String?
    let isFromCache: Bool
    let lastUpdatedAt: Date
}

enum CodexUsageState: Equatable {
    case idle
    case loading
    case loaded(CodexUsageSnapshot)
    case unavailable(CodexUsageUnavailableReason)
}

enum CodexUsageUnavailableReason: Equatable {
    case notAuthenticated
    case networkError
    case localFileMissing
    case serverError(String)

    var helpText: String {
        switch self {
        case .notAuthenticated:
            return "Run `codex-cli auth login` in terminal"
        case .networkError:
            return "Check your internet connection"
        case .localFileMissing:
            return "Ensure Codex CLI is installed and logged in"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

struct CodexUsageWindowPresentation: Equatable {
    let title: String
    let remainingText: String
    let detailText: String
    let badgeText: String?
}

struct CodexUsageSectionPresentation: Equatable {
    let statusText: String
    let rows: [CodexUsageWindowPresentation]

    static func make(from state: CodexUsageState, now: Date = Date()) -> Self {
        switch state {
        case .idle, .loading:
            return CodexUsageSectionPresentation(
                statusText: "Loading...",
                rows: [
                    CodexUsageWindowPresentation(
                        title: "5h Remaining",
                        remainingText: "--",
                        detailText: "Fetching latest quota",
                        badgeText: nil
                    ),
                    CodexUsageWindowPresentation(
                        title: "Week Remaining",
                        remainingText: "--",
                        detailText: "Fetching latest quota",
                        badgeText: nil
                    ),
                ]
            )
        case .loaded(let snapshot):
            return CodexUsageSectionPresentation(
                statusText: snapshot.isFromCache ? "Cached" : "Live",
                rows: [
                    CodexUsageWindowPresentation(
                        title: "5h Remaining",
                        remainingText: "\(snapshot.fiveHour.remainingPercent)%",
                        detailText: resetDescription(for: snapshot.fiveHour.resetAt, now: now),
                        badgeText: snapshot.isFromCache ? "Cached" : nil
                    ),
                    CodexUsageWindowPresentation(
                        title: "Week Remaining",
                        remainingText: "\(snapshot.week.remainingPercent)%",
                        detailText: resetDescription(for: snapshot.week.resetAt, now: now),
                        badgeText: snapshot.isFromCache ? "Cached" : nil
                    ),
                ]
            )
        case .unavailable(let reason):
            return CodexUsageSectionPresentation(
                statusText: "Unavailable",
                rows: [
                    CodexUsageWindowPresentation(
                        title: "5h Remaining",
                        remainingText: "--",
                        detailText: reason.helpText,
                        badgeText: "Retry"
                    ),
                    CodexUsageWindowPresentation(
                        title: "Week Remaining",
                        remainingText: "--",
                        detailText: reason == .notAuthenticated ? "Sign in to Codex CLI first" : "Check network connection",
                        badgeText: "Retry"
                    ),
                ]
            )
        }
    }

    private static func resetDescription(for resetAt: Date, now: Date) -> String {
        let interval = max(0, Int(resetAt.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = max(0, (interval % 3_600) / 60)

        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        }
        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        }
        return "Resets in \(max(1, minutes))m"
    }
}

struct CodexUsageServiceDependencies {
    var codexHomeURL: () -> URL
    var readData: (URL) throws -> Data
    var fetchData: (URLRequest) async throws -> (Data, URLResponse)
    var now: () -> Date

    static let live = CodexUsageServiceDependencies(
        codexHomeURL: {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        },
        readData: { url in
            try Data(contentsOf: url)
        },
        fetchData: { request in
            try await URLSession.shared.data(for: request)
        },
        now: { Date() }
    )
}

@MainActor
final class CodexUsageService: ObservableObject {
    static let shared = CodexUsageService(dependencies: .live)

    @Published private(set) var state: CodexUsageState = .idle

    private let dependencies: CodexUsageServiceDependencies
    private var hasRefreshedOnce = false

    init(dependencies: CodexUsageServiceDependencies) {
        self.dependencies = dependencies
    }

    func refreshIfNeeded() async {
        guard !hasRefreshedOnce else { return }
        hasRefreshedOnce = true
        await refresh()
    }

    func refresh() async {
        state = .loading

        do {
            let snapshot = try await loadLatestSnapshot()
            state = .loaded(snapshot)
        } catch let error as CodexUsageError {
            state = .unavailable(reasonFromError(error))
        } catch {
            if let cachedSnapshot = loadCachedSnapshot() {
                state = .loaded(cachedSnapshot)
            } else {
                state = .unavailable(.networkError)
            }
        }
    }

    private func reasonFromError(_ error: CodexUsageError) -> CodexUsageUnavailableReason {
        switch error {
        case .invalidBaseURL, .missingRateLimits:
            return .notAuthenticated
        case .unexpectedResponse:
            return .serverError("API response error")
        }
    }

    private func loadLatestSnapshot() async throws -> CodexUsageSnapshot {
        let codexHomeURL = dependencies.codexHomeURL()
        let authData = try dependencies.readData(codexHomeURL.appendingPathComponent("auth.json"))
        let authSnapshot = try Self.parseAuthSnapshot(from: authData)

        let configURL = codexHomeURL.appendingPathComponent("config.toml")
        let configString = try? String(data: dependencies.readData(configURL), encoding: .utf8)
        let baseURLString = Self.parseChatGPTBaseURL(from: configString)
            ?? "https://chatgpt.com/backend-api"

        let requestURL = try Self.makeUsageURL(from: baseURLString)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authSnapshot.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(authSnapshot.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")

        let (data, response) = try await dependencies.fetchData(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CodexUsageError.unexpectedResponse
        }

        return try Self.parseLiveSnapshot(from: data, now: dependencies.now())
    }

    private func loadCachedSnapshot() -> CodexUsageSnapshot? {
        let codexHomeURL = dependencies.codexHomeURL()
        let registryURL = codexHomeURL
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("registry.json")

        guard let data = try? dependencies.readData(registryURL) else {
            return nil
        }
        return try? Self.parseCachedSnapshot(from: data, now: dependencies.now())
    }

    func handleUnavailableTap() {
        Task {
            state = .loading
            do {
                let snapshot = try await loadLatestSnapshot()
                state = .loaded(snapshot)
            } catch {
                if loadCachedSnapshot() != nil {
                    state = .loaded(loadCachedSnapshot()!)
                } else {
                    state = .unavailable(.notAuthenticated)
                }
            }
        }
    }
}

extension CodexUsageService {
    static func parseAuthSnapshot(from data: Data) throws -> CodexAuthSnapshot {
        let authFile = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        return CodexAuthSnapshot(
            accessToken: authFile.tokens.accessToken,
            accountId: authFile.tokens.accountId
        )
    }

    static func parseChatGPTBaseURL(from config: String?) -> String? {
        guard let config else { return nil }

        let patterns = [
            #"(?m)^\s*chatgpt_base_url\s*=\s*"([^"]+)""#,
            #"(?m)^\s*chatgpt_base_url\s*=\s*'([^']+)'"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(config.startIndex..<config.endIndex, in: config)
            guard let match = regex.firstMatch(in: config, options: [], range: range),
                  let valueRange = Range(match.range(at: 1), in: config) else {
                continue
            }
            return String(config[valueRange])
        }

        return nil
    }

    static func makeUsageURL(from baseURLString: String) throws -> URL {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let path = trimmedBaseURL.contains("/backend-api") ? "/wham/usage" : "/api/codex/usage"
        guard let url = URL(string: trimmedBaseURL + path) else {
            throw CodexUsageError.invalidBaseURL
        }
        return url
    }

    static func parseLiveSnapshot(from data: Data, now: Date) throws -> CodexUsageSnapshot {
        let payload = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)
        guard let rateLimit = payload.rateLimit,
              let primaryWindow = rateLimit.primaryWindow,
              let secondaryWindow = rateLimit.secondaryWindow else {
            throw CodexUsageError.missingRateLimits
        }

        return CodexUsageSnapshot(
            fiveHour: makeWindow(from: primaryWindow),
            week: makeWindow(from: secondaryWindow),
            planType: payload.planType,
            isFromCache: false,
            lastUpdatedAt: now
        )
    }

    static func parseCachedSnapshot(from data: Data, now: Date) throws -> CodexUsageSnapshot {
        let registry = try JSONDecoder().decode(CodexRegistryFile.self, from: data)
        guard let activeAccountKey = registry.activeAccountKey,
              let account = registry.accounts.first(where: { $0.accountKey == activeAccountKey }),
              let lastUsage = account.lastUsage else {
            throw CodexUsageError.missingRateLimits
        }

        return CodexUsageSnapshot(
            fiveHour: makeWindow(from: lastUsage.primary),
            week: makeWindow(from: lastUsage.secondary),
            planType: lastUsage.planType ?? account.plan,
            isFromCache: true,
            lastUpdatedAt: account.lastUsageAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now
        )
    }

    private static func makeWindow(from payload: CodexUsageWindowPayload) -> CodexUsageWindow {
        CodexUsageWindow(
            remainingPercent: max(0, 100 - payload.usedPercent),
            usedPercent: payload.usedPercent,
            resetAt: Date(timeIntervalSince1970: TimeInterval(payload.resetAt))
        )
    }

    private static func makeWindow(from payload: CodexCachedUsageWindowPayload) -> CodexUsageWindow {
        CodexUsageWindow(
            remainingPercent: max(0, 100 - payload.usedPercent),
            usedPercent: payload.usedPercent,
            resetAt: Date(timeIntervalSince1970: TimeInterval(payload.resetsAt))
        )
    }
}

private enum CodexUsageError: Error {
    case invalidBaseURL
    case missingRateLimits
    case unexpectedResponse
}

private struct CodexAuthFile: Decodable {
    let tokens: Tokens

    struct Tokens: Decodable {
        let accessToken: String
        let accountId: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }
}

private struct CodexUsageAPIResponse: Decodable {
    let planType: String?
    let rateLimit: CodexUsageRateLimitPayload?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private struct CodexUsageRateLimitPayload: Decodable {
    let primaryWindow: CodexUsageWindowPayload?
    let secondaryWindow: CodexUsageWindowPayload?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexUsageWindowPayload: Decodable {
    let usedPercent: Int
    let resetAt: Int64

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }
}

private struct CodexRegistryFile: Decodable {
    let activeAccountKey: String?
    let accounts: [CodexRegistryAccount]

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case accounts
    }
}

private struct CodexRegistryAccount: Decodable {
    let accountKey: String
    let lastUsage: CodexRegistryUsageSnapshot?
    let lastUsageAt: Int64?
    let plan: String?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case plan
    }
}

private struct CodexRegistryUsageSnapshot: Decodable {
    let primary: CodexCachedUsageWindowPayload
    let secondary: CodexCachedUsageWindowPayload
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct CodexCachedUsageWindowPayload: Decodable {
    let usedPercent: Int
    let resetsAt: Int64

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
    }
}
