import Foundation
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "ClaudeUsageService")

@MainActor @Observable
final class ClaudeUsageService {
    static let shared = ClaudeUsageService()

    var currentUsage: QuotaPeriod?
    var isLoading = false
    var error: String?
    var isConnected = false

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 60

    private init() {}

    func connectAndStartPolling() {
        AppSettings.isUsageEnabled = true
        error = nil
        startPolling()
    }

    func startPolling() {
        guard AppSettings.isUsageEnabled else {
            logger.info("Usage not enabled, skipping polling")
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
        guard let accessToken = KeychainManager.getAccessToken() else {
            error = "Keychain access required"
            isConnected = false
            AppSettings.isUsageEnabled = false
            stopPolling()
            return
        }

        isConnected = true

        isLoading = true
        error = nil

        defer { isLoading = false }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            error = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Notchi", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Invalid response"
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    error = "Token expired"
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
