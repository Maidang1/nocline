import Foundation
import XCTest
@testable import notchi

@MainActor
final class CodexUsageServiceTests: XCTestCase {
    func testParseAuthSnapshotReadsTokenAndAccountId() throws {
        let data = Data("""
        {
          "tokens": {
            "access_token": "access-token",
            "account_id": "account-123"
          }
        }
        """.utf8)

        let snapshot = try CodexUsageService.parseAuthSnapshot(from: data)

        XCTAssertEqual(snapshot, CodexAuthSnapshot(accessToken: "access-token", accountId: "account-123"))
    }

    func testParseChatGPTBaseURLReadsQuotedValue() {
        let config = """
        model = "gpt-5.4"
        chatgpt_base_url = "https://example.com/backend-api"
        """

        XCTAssertEqual(
            CodexUsageService.parseChatGPTBaseURL(from: config),
            "https://example.com/backend-api"
        )
    }

    func testMakeUsageURLUsesWhamPathForBackendAPI() throws {
        let url = try CodexUsageService.makeUsageURL(from: "https://chatgpt.com/backend-api")
        XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
    }

    func testMakeUsageURLUsesCodexAPIPathForNonBackendAPI() throws {
        let url = try CodexUsageService.makeUsageURL(from: "https://example.com")
        XCTAssertEqual(url.absoluteString, "https://example.com/api/codex/usage")
    }

    func testParseLiveSnapshotMapsRemainingPercentAndResetTimes() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_at": 1700003600
            },
            "secondary_window": {
              "used_percent": 12,
              "limit_window_seconds": 604800,
              "reset_at": 1700086400
            }
          }
        }
        """.utf8)

        let snapshot = try CodexUsageService.parseLiveSnapshot(from: data, now: now)

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertFalse(snapshot.isFromCache)
        XCTAssertEqual(snapshot.lastUpdatedAt, now)
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 42)
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 58)
        XCTAssertEqual(snapshot.fiveHour.resetAt, Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertEqual(snapshot.week.usedPercent, 12)
        XCTAssertEqual(snapshot.week.remainingPercent, 88)
        XCTAssertEqual(snapshot.week.resetAt, Date(timeIntervalSince1970: 1_700_086_400))
    }

    func testParseCachedSnapshotReadsActiveAccountUsage() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("""
        {
          "active_account_key": "active",
          "accounts": [
            {
              "account_key": "active",
              "last_usage_at": 1700000100,
              "plan": "unknown",
              "last_usage": {
                "primary": {
                  "used_percent": 3,
                  "window_minutes": 300,
                  "resets_at": 1700000200
                },
                "secondary": {
                  "used_percent": 9,
                  "window_minutes": 10080,
                  "resets_at": 1700000300
                },
                "plan_type": "plus"
              }
            }
          ]
        }
        """.utf8)

        let snapshot = try CodexUsageService.parseCachedSnapshot(from: data, now: now)

        XCTAssertTrue(snapshot.isFromCache)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.lastUpdatedAt, Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 97)
        XCTAssertEqual(snapshot.week.remainingPercent, 91)
    }

    func testRefreshFallsBackToCacheWhenAPIRequestFails() async {
        let codexHome = URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
        let service = CodexUsageService(
            dependencies: makeDependencies(
                codexHome: codexHome,
                files: [
                    "auth.json": Data("""
                    {
                      "tokens": {
                        "access_token": "access-token",
                        "account_id": "account-123"
                      }
                    }
                    """.utf8),
                    "registry.json": Data("""
                    {
                      "active_account_key": "active",
                      "accounts": [
                        {
                          "account_key": "active",
                          "last_usage_at": 1700000100,
                          "last_usage": {
                            "primary": {
                              "used_percent": 10,
                              "window_minutes": 300,
                              "resets_at": 1700000200
                            },
                            "secondary": {
                              "used_percent": 20,
                              "window_minutes": 10080,
                              "resets_at": 1700000300
                            },
                            "plan_type": "pro"
                          }
                        }
                      ]
                    }
                    """.utf8),
                ],
                fetchData: { _ in
                    throw URLError(.cannotConnectToHost)
                }
            )
        )

        await service.refresh()

        guard case .loaded(let snapshot) = service.state else {
            return XCTFail("Expected cached snapshot")
        }
        XCTAssertTrue(snapshot.isFromCache)
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 90)
        XCTAssertEqual(snapshot.week.remainingPercent, 80)
    }

    func testRefreshReturnsUnavailableWhenAPIFailsAndNoCacheExists() async {
        let codexHome = URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
        let service = CodexUsageService(
            dependencies: makeDependencies(
                codexHome: codexHome,
                files: [
                    "auth.json": Data("""
                    {
                      "tokens": {
                        "access_token": "access-token",
                        "account_id": "account-123"
                      }
                    }
                    """.utf8),
                ],
                fetchData: { _ in
                    throw URLError(.cannotConnectToHost)
                }
            )
        )

        await service.refresh()

        XCTAssertEqual(service.state, .unavailable)
    }

    func testRefreshIfNeededOnlyFetchesOnce() async {
        let codexHome = URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)
        var fetchCount = 0
        let service = CodexUsageService(
            dependencies: makeDependencies(
                codexHome: codexHome,
                files: [
                    "auth.json": Data("""
                    {
                      "tokens": {
                        "access_token": "access-token",
                        "account_id": "account-123"
                      }
                    }
                    """.utf8),
                ],
                fetchData: { _ in
                    fetchCount += 1
                    let response = HTTPURLResponse(
                        url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    let body = Data("""
                    {
                      "plan_type": "plus",
                      "rate_limit": {
                        "primary_window": {
                          "used_percent": 5,
                          "reset_at": 1700000200
                        },
                        "secondary_window": {
                          "used_percent": 15,
                          "reset_at": 1700000300
                        }
                      }
                    }
                    """.utf8)
                    return (body, response)
                }
            )
        )

        await service.refreshIfNeeded()
        await service.refreshIfNeeded()

        XCTAssertEqual(fetchCount, 1)
    }

    func testSectionPresentationShowsCachedRows() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = CodexUsageSnapshot(
            fiveHour: CodexUsageWindow(
                remainingPercent: 91,
                usedPercent: 9,
                resetAt: Date(timeIntervalSince1970: 1_700_003_600)
            ),
            week: CodexUsageWindow(
                remainingPercent: 88,
                usedPercent: 12,
                resetAt: Date(timeIntervalSince1970: 1_700_086_400)
            ),
            planType: "pro",
            isFromCache: true,
            lastUpdatedAt: now
        )

        let presentation = CodexUsageSectionPresentation.make(from: .loaded(snapshot), now: now)

        XCTAssertEqual(presentation.statusText, "Cached")
        XCTAssertEqual(presentation.rows.first?.remainingText, "91%")
        XCTAssertEqual(presentation.rows.first?.badgeText, "Cached")
        XCTAssertEqual(presentation.rows.last?.remainingText, "88%")
    }

    func testSectionPresentationShowsUnavailableRows() {
        let presentation = CodexUsageSectionPresentation.make(from: .unavailable)

        XCTAssertEqual(presentation.statusText, "Unavailable")
        XCTAssertEqual(presentation.rows.map(\.detailText), ["Unavailable", "Unavailable"])
    }

    private func makeDependencies(
        codexHome: URL,
        files: [String: Data],
        fetchData: @escaping (URLRequest) async throws -> (Data, URLResponse)
    ) -> CodexUsageServiceDependencies {
        CodexUsageServiceDependencies(
            codexHomeURL: { codexHome },
            readData: { url in
                if let data = files[url.lastPathComponent] {
                    return data
                }
                throw CocoaError(.fileNoSuchFile)
            },
            fetchData: fetchData,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }
}
