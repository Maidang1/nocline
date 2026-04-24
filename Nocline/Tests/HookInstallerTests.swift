import Foundation
import XCTest
@testable import Nocline

final class HookInstallerTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nocline-hook-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        CodexConfigDirectoryResolver.resetTestingHooks()
        CodexCLIResolver.resetTestingHooks()
        CodexHookInstaller.resetTestingHooks()
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testCodexConfigDirectoryResolverUsesProcessEnvironment() {
        CodexConfigDirectoryResolver.testHooks = .init(
            environment: { ["CODEX_HOME": "/tmp/codex-home"] },
            isExecutableFile: { _ in false },
            runProcess: { _, _, _ in
                XCTFail("Shell probe should stay idle when CODEX_HOME is present")
                return nil
            }
        )

        let resolution = CodexConfigDirectoryResolver.resolve()

        XCTAssertEqual(resolution.path, "/tmp/codex-home")
        XCTAssertEqual(resolution.source, .environment)
    }

    func testCodexConfigDirectoryResolverUsesShellProbe() {
        var processCalls: [[String]] = []
        CodexConfigDirectoryResolver.testHooks = .init(
            environment: { ["SHELL": "/mock/zsh"] },
            isExecutableFile: { path in path == "/mock/zsh" },
            runProcess: { _, arguments, _ in
                processCalls.append(arguments)
                if arguments == ["-lc", "printf '%s' \"$CODEX_HOME\""] {
                    return "/tmp/from-codex-shell\n"
                }
                return nil
            }
        )

        let resolution = CodexConfigDirectoryResolver.resolve()

        XCTAssertEqual(resolution.path, "/tmp/from-codex-shell")
        XCTAssertEqual(resolution.source, .shell)
        XCTAssertEqual(processCalls, [["-lc", "printf '%s' \"$CODEX_HOME\""]])
    }

    func testCodexConfigDirectoryResolverFallsBackToDefaultHome() {
        CodexConfigDirectoryResolver.testHooks = .init(
            environment: { [:] },
            isExecutableFile: { _ in false },
            runProcess: { _, _, _ in nil }
        )

        let resolution = CodexConfigDirectoryResolver.resolve()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertEqual(resolution.path, "\(home)/.codex")
        XCTAssertEqual(resolution.source, .fallback)
    }

    func testCodexCLIResolverUsesPathCandidateAndExtractsVersion() {
        CodexCLIResolver.testHooks = .init(
            environment: { ["PATH": "/mock/bin", "SHELL": "/mock/zsh"] },
            isExecutableFile: { path in
                path == "/mock/bin/codex" || path == "/mock/zsh"
            },
            runProcess: { executablePath, arguments, _ in
                if executablePath == "/mock/zsh", arguments == ["-lc", "command -v codex"] {
                    return "/mock/bin/codex\n"
                }
                if executablePath == "/mock/bin/codex", arguments == ["--version"] {
                    return "codex-cli 0.124.0\n"
                }
                return nil
            }
        )

        XCTAssertEqual(CodexCLIResolver.resolveExecutablePath(), "/mock/bin/codex")
        XCTAssertEqual(CodexCLIResolver.resolveVersion(at: "/mock/bin/codex"), "0.124.0")
        XCTAssertEqual(CodexCLIResolver.extractVersion(from: "codex 1.2.3\n"), "1.2.3")
    }

    func testCodexUpsertHookSettingsAddsRequiredEvents() throws {
        let data = try XCTUnwrap(CodexHookInstaller.upsertHookSettings(
            from: nil,
            command: CodexHookInstaller.hookCommand
        ))

        XCTAssertTrue(CodexHookInstaller.isHookInstalled(in: data))

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])

        XCTAssertEqual(sessionStart.first?["matcher"] as? String, "startup|resume|clear")
        XCTAssertEqual(preToolUse.first?["matcher"] as? String, "Bash")
        XCTAssertNotNil(hooks["PermissionRequest"])
        XCTAssertNotNil(hooks["Stop"])
    }

    func testCodexUpsertHookSettingsPreservesOtherHooksAndDeduplicatesCommand() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": CodexHookInstaller.hookCommand],
                            ["type": "command", "command": "echo other"],
                        ],
                    ],
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "~/.codex/hooks/notchi-codex-hook.sh"],
                        ],
                    ],
                ],
            ],
            "custom": true,
        ])

        let updated = try XCTUnwrap(CodexHookInstaller.upsertHookSettings(
            from: existing,
            command: CodexHookInstaller.hookCommand
        ))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let commands = preToolUse
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }

        XCTAssertEqual(json["custom"] as? Bool, true)
        XCTAssertTrue(commands.contains("echo other"))
        XCTAssertEqual(commands.filter { $0 == CodexHookInstaller.hookCommand }.count, 1)
    }

    func testCodexInstallReportsFeatureEnableFailure() throws {
        let codexHome = tempDirectoryURL.appendingPathComponent("codex-home", isDirectory: true)
        let scriptURL = tempDirectoryURL.appendingPathComponent("nocline-codex-hook.sh")
        try "#!/bin/bash\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        var processCalls: [ResolverProcessCall] = []
        CodexConfigDirectoryResolver.testHooks = .init(
            environment: { ["CODEX_HOME": codexHome.path] },
            isExecutableFile: { _ in false },
            runProcess: { _, _, _ in nil }
        )
        CodexCLIResolver.testHooks = .init(
            environment: { ["PATH": "/mock/bin"] },
            isExecutableFile: { path in path == "/mock/bin/codex" },
            runProcess: { executablePath, arguments, environment in
                processCalls.append(ResolverProcessCall(
                    executablePath: executablePath,
                    arguments: arguments,
                    environment: environment
                ))
                return nil
            }
        )
        CodexHookInstaller.testHooks = .init(
            bundledHookScriptURL: { scriptURL }
        )

        let success = CodexHookInstaller.installIfNeeded()

        XCTAssertFalse(success)
        XCTAssertEqual(processCalls.first?.executablePath, "/mock/bin/codex")
        XCTAssertEqual(processCalls.first?.arguments, ["features", "enable", "codex_hooks"])
        XCTAssertNil(try? Data(contentsOf: codexHome.appendingPathComponent("hooks.json")))
    }
}

private struct ResolverProcessCall: Equatable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]?
}
