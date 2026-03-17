import Foundation
import XCTest
@testable import notchi

private struct TestPollTimer: ClaudeUsagePollTimer {
    func invalidate() {}
}

@MainActor
private final class PollSchedulerSpy {
    private(set) var intervals: [TimeInterval] = []

    func schedule(after interval: TimeInterval, handler: @escaping () -> Void) -> any ClaudeUsagePollTimer {
        intervals.append(interval)
        return TestPollTimer()
    }
}

@MainActor
final class ClaudeUsageServiceTests: XCTestCase {
    func testSuccessfulFetchClearsStaleStateAndSchedulesNormalPolling() async throws {
        let scheduler = PollSchedulerSpy()
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            fetchUsage: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.77")
                return (self.makeSuccessPayload(utilization: 42), self.makeResponse(statusCode: 200))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        service.currentUsage = makeQuotaPeriod(utilization: 8)
        service.error = "Old error"
        service.statusMessage = "Stale, retrying in 120s"
        service.isUsageStale = true
        service.recoveryAction = .retry

        await service.performFetch(with: "token")

        XCTAssertEqual(service.currentUsage?.usagePercentage, 42)
        XCTAssertNil(service.error)
        XCTAssertNil(service.statusMessage)
        XCTAssertFalse(service.isUsageStale)
        XCTAssertEqual(service.recoveryAction, .none)
        XCTAssertEqual(scheduler.intervals, [60])
    }

    func testManualRetryResetsRateLimitCounter() async throws {
        let scheduler = PollSchedulerSpy()
        var now = Date(timeIntervalSince1970: 100)
        var responses: [(Data, URLResponse)] = [
            (Data(), makeResponse(statusCode: 429)),
            (Data(), makeResponse(statusCode: 429)),
            (Data(), makeResponse(statusCode: 429)),
            (Data(), makeResponse(statusCode: 429)),
        ]
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            getCachedOAuthToken: { "token" },
            now: { now },
            fetchUsage: { _ in
                responses.removeFirst()
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        service.startPolling()
        await Task.yield()
        await Task.yield()
        now = now.addingTimeInterval(20)
        await service.performFetch(with: "token")
        await service.performFetch(with: "token")
        now = now.addingTimeInterval(11)
        service.retryNow()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(service.error, "Rate limited, retrying in 120s")
        XCTAssertEqual(scheduler.intervals, [120, 240, 480, 120])
    }

    func testRateLimitWithoutCachedUsageShowsRetryState() async throws {
        let scheduler = PollSchedulerSpy()
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            fetchUsage: { _ in
                (Data(), self.makeResponse(statusCode: 429, headers: ["Retry-After": "0"]))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        await service.performFetch(with: "token")

        XCTAssertNil(service.currentUsage)
        XCTAssertEqual(service.error, "Rate limited, retrying in 120s")
        XCTAssertNil(service.statusMessage)
        XCTAssertFalse(service.isUsageStale)
        XCTAssertEqual(service.recoveryAction, .retry)
        XCTAssertEqual(scheduler.intervals, [120])
    }

    func testPositiveRetryAfterHeaderRaisesBackoffDelay() async throws {
        let scheduler = PollSchedulerSpy()
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            fetchUsage: { _ in
                (Data(), self.makeResponse(statusCode: 429, headers: ["Retry-After": "300"]))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        await service.performFetch(with: "token")

        XCTAssertEqual(service.error, "Rate limited, retrying in 300s")
        XCTAssertEqual(scheduler.intervals, [300])
    }

    func testRateLimitWithCachedUsageKeepsUsageButMarksItStale() async throws {
        let scheduler = PollSchedulerSpy()
        var responses: [(Data, URLResponse)] = [
            (makeSuccessPayload(utilization: 55), makeResponse(statusCode: 200)),
            (Data(), makeResponse(statusCode: 429)),
        ]
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            fetchUsage: { _ in
                responses.removeFirst()
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        await service.performFetch(with: "token")
        await service.performFetch(with: "token")

        XCTAssertEqual(service.currentUsage?.usagePercentage, 55)
        XCTAssertNil(service.error)
        XCTAssertEqual(service.statusMessage, "Stale, retrying in 120s")
        XCTAssertTrue(service.isUsageStale)
        XCTAssertEqual(service.recoveryAction, .retry)
        XCTAssertEqual(scheduler.intervals, [60, 120])
    }

    func testRetryCooldownShowsVisibleFeedback() async throws {
        let scheduler = PollSchedulerSpy()
        let now = Date(timeIntervalSince1970: 100)
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            getCachedOAuthToken: { "token" },
            now: { now },
            fetchUsage: { _ in
                (Data(), self.makeResponse(statusCode: 429))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        service.startPolling()
        await Task.yield()
        await Task.yield()
        service.retryNow()

        XCTAssertEqual(service.statusMessage, "Please wait before retrying again")
        XCTAssertEqual(service.recoveryAction, .retry)
        XCTAssertEqual(scheduler.intervals, [120])
    }

    func testMissingClaudeCLIStopsBeforeSendingRequest() async throws {
        let scheduler = PollSchedulerSpy()
        var fetchCalled = false
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { nil },
            fetchUsage: { _ in
                fetchCalled = true
                return (Data(), self.makeResponse(statusCode: 200))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        await service.performFetch(with: "token")

        XCTAssertFalse(fetchCalled)
        XCTAssertEqual(service.error, "Claude CLI not found")
        XCTAssertNil(service.statusMessage)
        XCTAssertFalse(service.isUsageStale)
        XCTAssertEqual(service.recoveryAction, .reconnect)
        XCTAssertTrue(scheduler.intervals.isEmpty)
    }

    func testConnectAndStartPollingUsesInteractiveTokenLookup() async throws {
        let scheduler = PollSchedulerSpy()
        var getAccessTokenCalls = 0
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            getAccessToken: {
                getAccessTokenCalls += 1
                return nil
            },
            fetchUsage: { _ in
                XCTFail("fetchUsage should not run without a token")
                return (Data(), self.makeResponse(statusCode: 200))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        service.connectAndStartPolling()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(getAccessTokenCalls, 1)
        XCTAssertEqual(service.error, "Keychain access required")
        XCTAssertEqual(service.recoveryAction, .reconnect)
        XCTAssertTrue(scheduler.intervals.isEmpty)
        XCTAssertFalse(AppSettings.isUsageEnabled)
    }

    func testStartPollingDisablesUsageWhenNoCachedTokenExists() async throws {
        let scheduler = PollSchedulerSpy()
        var getCachedTokenCalls = 0
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            getCachedOAuthToken: {
                getCachedTokenCalls += 1
                return nil
            },
            fetchUsage: { _ in
                XCTFail("fetchUsage should not run without a cached token")
                return (Data(), self.makeResponse(statusCode: 200))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        AppSettings.isUsageEnabled = true
        service.startPolling()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(getCachedTokenCalls, 1)
        XCTAssertFalse(AppSettings.isUsageEnabled)
        XCTAssertFalse(service.isConnected)
        XCTAssertTrue(scheduler.intervals.isEmpty)
    }

    func testUnauthorizedFetchRefreshesTokenOnceAndRecovers() async throws {
        let scheduler = PollSchedulerSpy()
        var refreshCalls = 0
        var clearCachedTokenCalls = 0
        var authHeaders: [String] = []
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            refreshAccessTokenSilently: {
                refreshCalls += 1
                return "new-token"
            },
            clearCachedOAuthToken: {
                clearCachedTokenCalls += 1
            },
            fetchUsage: { request in
                let authHeader = request.value(forHTTPHeaderField: "Authorization") ?? "<missing>"
                authHeaders.append(authHeader)
                if authHeader == "Bearer old-token" {
                    return (Data(), self.makeResponse(statusCode: 401))
                }
                return (self.makeSuccessPayload(utilization: 33), self.makeResponse(statusCode: 200))
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        await service.performFetch(with: "old-token")

        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(clearCachedTokenCalls, 1)
        XCTAssertEqual(authHeaders, ["Bearer old-token", "Bearer new-token"])
        XCTAssertEqual(service.currentUsage?.usagePercentage, 33)
        XCTAssertNil(service.error)
        XCTAssertNil(service.statusMessage)
        XCTAssertEqual(service.recoveryAction, .none)
        XCTAssertEqual(scheduler.intervals, [60])
    }

    func testThreeConsecutiveRateLimitsRefreshTokenAndRetry() async throws {
        let scheduler = PollSchedulerSpy()
        var refreshCalls = 0
        var authHeaders: [String] = []
        var responses: [(Data, URLResponse)] = [
            (Data(), makeResponse(statusCode: 429)),
            (Data(), makeResponse(statusCode: 429)),
            (Data(), makeResponse(statusCode: 429)),
            (makeSuccessPayload(utilization: 64), makeResponse(statusCode: 200)),
        ]
        let dependencies = makeDependencies(
            scheduler: scheduler,
            resolveUserAgent: { "claude-code/2.1.77" },
            refreshAccessTokenSilently: {
                refreshCalls += 1
                return "fresh-token"
            },
            fetchUsage: { request in
                authHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "<missing>")
                return responses.removeFirst()
            }
        )

        let service = ClaudeUsageService(dependencies: dependencies)
        await service.performFetch(with: "old-token")
        await service.performFetch(with: "old-token")
        await service.performFetch(with: "old-token")

        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(authHeaders, ["Bearer old-token", "Bearer old-token", "Bearer old-token", "Bearer fresh-token"])
        XCTAssertEqual(service.currentUsage?.usagePercentage, 64)
        XCTAssertNil(service.error)
        XCTAssertNil(service.statusMessage)
        XCTAssertFalse(service.isUsageStale)
        XCTAssertEqual(service.recoveryAction, .none)
        XCTAssertEqual(scheduler.intervals, [120, 240, 60])
    }

    private func makeDependencies(
        scheduler: PollSchedulerSpy,
        resolveUserAgent: @escaping () -> String?,
        getAccessToken: @escaping () -> String? = { nil },
        getCachedOAuthToken: @escaping () -> String? = { nil },
        refreshAccessTokenSilently: @escaping () -> String? = { nil },
        clearCachedOAuthToken: @escaping () -> Void = {},
        now: @escaping () -> Date = { Date() },
        fetchUsage: @escaping (URLRequest) async throws -> (Data, URLResponse)
    ) -> ClaudeUsageServiceDependencies {
        ClaudeUsageServiceDependencies(
            fetchUsage: fetchUsage,
            getAccessToken: getAccessToken,
            getCachedOAuthToken: getCachedOAuthToken,
            refreshAccessTokenSilently: refreshAccessTokenSilently,
            clearCachedOAuthToken: clearCachedOAuthToken,
            resolveUserAgent: resolveUserAgent,
            pollJitter: { 0 },
            now: now,
            schedulePoll: { interval, handler in
                scheduler.schedule(after: interval, handler: handler)
            }
        )
    }

    private func makeSuccessPayload(utilization: Double) -> Data {
        let json = """
        {
          "five_hour": {
            "utilization": \(utilization),
            "resets_at": "2099-01-01T01:00:00Z"
          },
          "seven_day": null
        }
        """
        return Data(json.utf8)
    }

    private func makeQuotaPeriod(utilization: Double) -> QuotaPeriod {
        QuotaPeriod(utilization: utilization, resetsAt: "2099-01-01T01:00:00Z")
    }

    private func makeResponse(statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}
