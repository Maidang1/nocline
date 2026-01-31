import Foundation
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "ClaudeUsageService")

@MainActor @Observable
final class ClaudeUsageService {
    static let shared = ClaudeUsageService()

    var currentUsage: QuotaPeriod?
    var isLoading = false
    var error: String?

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 60

    private init() {}

    func startPolling() {
        guard KeychainManager.hasCredentials else {
            logger.info("No credentials configured, skipping polling")
            return
        }

        stopPolling()

        Task {
            await fetchUsage()
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }

        logger.info("Started usage polling (every \(self.pollInterval)s)")
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func fetchUsage() async {
        guard let sessionKey = KeychainManager.getSessionKey(),
              let orgId = KeychainManager.getOrganizationId() else {
            error = "Credentials not configured"
            return
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        let urlString = "https://claude.ai/api/organizations/\(orgId)/usage"
        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Use full cookie string if it contains multiple cookies, otherwise wrap as sessionKey
        let cookieValue = sessionKey.contains(";") ? sessionKey : "sessionKey=\(sessionKey)"
        request.setValue(cookieValue, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "user-agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Invalid response"
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    error = "Invalid credentials"
                } else {
                    error = "HTTP \(httpResponse.statusCode)"
                }
                logger.warning("API error: HTTP \(httpResponse.statusCode)")
                return
            }

            let usageResponse = try JSONDecoder().decode(UsageResponse.self, from: data)
            currentUsage = usageResponse.fiveHour

            logger.info("Usage fetched: \(self.currentUsage?.usagePercentage ?? 0)%")

        } catch {
            self.error = "Network error"
            logger.error("Fetch failed: \(error.localizedDescription)")
        }
    }
}
