import Foundation
import os.log

func runProcessWithTimeout(
    executablePath: String,
    arguments: [String],
    environment: [String: String]? = nil,
    commandTimeout: TimeInterval
) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.environment = environment

    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = Pipe()

    let completion = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        completion.signal()
    }

    do {
        try process.run()
    } catch {
        return nil
    }

    if completion.wait(timeout: .now() + commandTimeout) == .timedOut {
        process.terminate()
        return nil
    }

    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }
    return output
}

func extractAbsolutePath(from output: String) -> String? {
    output
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .last { $0.hasPrefix("/") || $0.hasPrefix("~") }
}

private let codexLogger = Logger(subsystem: "com.ruban.notchi", category: "CodexHookInstaller")

enum CodexConfigDirectorySource: String {
    case environment = "env"
    case shell = "shell"
    case fallback = "default"
}

struct CodexConfigDirectoryResolution {
    let path: String
    let source: CodexConfigDirectorySource
    let shouldCache: Bool

    var directoryURL: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var hooksJSONURL: URL {
        directoryURL.appendingPathComponent("hooks.json")
    }

    var hooksDirectoryURL: URL {
        directoryURL.appendingPathComponent("hooks", isDirectory: true)
    }

    var hookScriptURL: URL {
        hooksDirectoryURL.appendingPathComponent(CodexHookInstaller.hookScriptFileName)
    }

    var configURL: URL {
        directoryURL.appendingPathComponent("config.toml")
    }

    var sessionsDirectoryURL: URL {
        directoryURL.appendingPathComponent("sessions", isDirectory: true)
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + String(path.dropFirst(home.count))
    }
}

enum CodexConfigDirectoryResolver {
    struct TestHooks {
        var environment: () -> [String: String]
        var isExecutableFile: (String) -> Bool
        var runProcess: (
            _ executablePath: String,
            _ arguments: [String],
            _ environment: [String: String]?
        ) -> String?
    }

    private static let commandTimeout: TimeInterval = 2
    private static var cachedResolution: CodexConfigDirectoryResolution?
    static var testHooks = makeDefaultTestHooks()

    static func resolve() -> CodexConfigDirectoryResolution {
        if let cachedResolution {
            return cachedResolution
        }

        let environment = testHooks.environment()
        let resolved: CodexConfigDirectoryResolution

        if let path = normalize(path: environment["CODEX_HOME"]) {
            resolved = CodexConfigDirectoryResolution(path: path, source: .environment, shouldCache: true)
        } else {
            switch resolveViaShell(environment: environment) {
            case .resolved(let path):
                resolved = CodexConfigDirectoryResolution(path: path, source: .shell, shouldCache: true)
            case .unset:
                let fallback = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true)
                    .path
                resolved = CodexConfigDirectoryResolution(path: fallback, source: .fallback, shouldCache: true)
            case .probeFailed:
                let fallback = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true)
                    .path
                resolved = CodexConfigDirectoryResolution(path: fallback, source: .fallback, shouldCache: false)
            }
        }

        if resolved.shouldCache {
            cachedResolution = resolved
        }
        return resolved
    }

    static func resetTestingHooks() {
        testHooks = makeDefaultTestHooks()
        cachedResolution = nil
    }

    private static func makeDefaultTestHooks() -> TestHooks {
        TestHooks(
            environment: { ProcessInfo.processInfo.environment },
            isExecutableFile: { path in
                FileManager.default.isExecutableFile(atPath: path)
            },
            runProcess: { executablePath, arguments, environment in
                runProcessWithTimeout(
                    executablePath: executablePath,
                    arguments: arguments,
                    environment: environment,
                    commandTimeout: commandTimeout
                )
            }
        )
    }

    private enum ShellResolution {
        case resolved(String)
        case unset
        case probeFailed
    }

    private enum ShellProbeResult {
        case resolved(String)
        case unset
        case failed
    }

    private static func resolveViaShell(environment: [String: String]) -> ShellResolution {
        let probeCommand = "printf '%s' \"$CODEX_HOME\""
        var sawSuccessfulProbe = false
        var sawFailedProbe = false

        for shellPath in shellCandidates(from: environment) {
            guard testHooks.isExecutableFile(shellPath) else { continue }

            switch runShellProbe(executablePath: shellPath, arguments: ["-lc", probeCommand]) {
            case .resolved(let path):
                return .resolved(path)
            case .unset:
                sawSuccessfulProbe = true
            case .failed:
                sawFailedProbe = true
            }

            switch runShellProbe(executablePath: shellPath, arguments: ["-ic", probeCommand]) {
            case .resolved(let path):
                return .resolved(path)
            case .unset:
                sawSuccessfulProbe = true
            case .failed:
                sawFailedProbe = true
            }
        }

        if sawFailedProbe {
            return .probeFailed
        }

        return sawSuccessfulProbe ? .unset : .probeFailed
    }

    private static func runShellProbe(executablePath: String, arguments: [String]) -> ShellProbeResult {
        guard let output = testHooks.runProcess(executablePath, arguments, nil) else {
            return .failed
        }

        guard let path = normalize(path: extractAbsolutePath(from: output)) else {
            return .unset
        }

        return .resolved(path)
    }

    private static func normalize(path rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }

        return URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private static func shellCandidates(from environment: [String: String]) -> [String] {
        var seenShells: Set<String> = []
        return [environment["SHELL"], "/bin/zsh", "/bin/bash"]
            .compactMap { $0 }
            .filter { seenShells.insert($0).inserted }
    }
}

enum CodexCLIResolver {
    struct TestHooks {
        var environment: () -> [String: String]
        var isExecutableFile: (String) -> Bool
        var runProcess: (
            _ executablePath: String,
            _ arguments: [String],
            _ environment: [String: String]?
        ) -> String?
    }

    private static let commandTimeout: TimeInterval = 2
    static var testHooks = makeDefaultTestHooks()

    static func resolveExecutablePath() -> String? {
        knownExecutablePaths().first
    }

    static func resetTestingHooks() {
        testHooks = makeDefaultTestHooks()
    }

    static func enableHooksFeature(at codexPath: String, codexHome: String) -> Bool {
        var environment = versionProbeEnvironment(for: codexPath)
        environment["CODEX_HOME"] = codexHome
        return testHooks.runProcess(
            codexPath,
            ["features", "enable", "codex_hooks"],
            environment
        ) != nil
    }

    private static func makeDefaultTestHooks() -> TestHooks {
        TestHooks(
            environment: { ProcessInfo.processInfo.environment },
            isExecutableFile: { path in
                FileManager.default.isExecutableFile(atPath: path)
            },
            runProcess: { executablePath, arguments, environment in
                runProcessWithTimeout(
                    executablePath: executablePath,
                    arguments: arguments,
                    environment: environment,
                    commandTimeout: commandTimeout
                )
            }
        )
    }

    private static func knownExecutablePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = testHooks.environment()
        let explicitPaths = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        let pathDerivedCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/codex" }
        let shellResolvedPath = resolveCommandPathViaShell(environment: environment).map { [$0] } ?? []

        var resolvedPaths: [String] = []
        var seenPaths: Set<String> = []

        for path in explicitPaths + pathDerivedCandidates + shellResolvedPath {
            guard path.hasPrefix("/") else { continue }
            guard seenPaths.insert(path).inserted else { continue }
            guard testHooks.isExecutableFile(path) else { continue }
            resolvedPaths.append(path)
        }

        return resolvedPaths
    }

    static func resolveCommandPathViaShell(environment: [String: String]) -> String? {
        for shellPath in shellCandidates(from: environment) {
            guard testHooks.isExecutableFile(shellPath) else { continue }
            if let resolvedPath = resolveCommandPathViaShell(
                executablePath: shellPath,
                arguments: ["-lc", "command -v codex"]
            ) {
                return resolvedPath
            }

            if let resolvedPath = resolveCommandPathViaShell(
                executablePath: shellPath,
                arguments: ["-ic", "command -v codex"]
            ) {
                return resolvedPath
            }
        }

        return nil
    }

    private static func resolveCommandPathViaShell(
        executablePath: String,
        arguments: [String]
    ) -> String? {
        guard let output = testHooks.runProcess(executablePath, arguments, nil) else {
            return nil
        }

        guard let resolvedPath = extractExecutablePath(from: output) else {
            return nil
        }

        guard testHooks.isExecutableFile(resolvedPath) else {
            return nil
        }

        return resolvedPath
    }

    static func extractExecutablePath(from output: String) -> String? {
        extractAbsolutePath(from: output)
    }

    static func resolveVersion(at path: String) -> String? {
        let environment = versionProbeEnvironment(for: path)
        if let version = resolveVersion(
            executablePath: path,
            arguments: ["--version"],
            environment: environment
        ) {
            return version
        }

        return resolveVersionViaShell(at: path, environment: environment)
    }

    static func extractVersion(from output: String) -> String? {
        let versionLine = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                line.contains("codex") || line.first?.isNumber == true
            }

        guard let versionLine else { return nil }
        let parts = versionLine.split(whereSeparator: \.isWhitespace)
        if let version = parts.last, version.contains(".") {
            return String(version)
        }
        guard let version = parts.first else { return nil }
        return String(version)
    }

    private static func shellCandidates(from environment: [String: String]) -> [String] {
        var seenShells: Set<String> = []
        return [environment["SHELL"], "/bin/zsh", "/bin/bash"]
            .compactMap { $0 }
            .filter { seenShells.insert($0).inserted }
    }

    private static func versionProbeEnvironment(for path: String) -> [String: String] {
        var environment = testHooks.environment()
        let executableDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let existingPath = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath: String
        if let existingPath, !existingPath.isEmpty {
            basePath = existingPath
        } else {
            basePath = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
        environment["PATH"] = "\(executableDirectory):\(basePath)"
        return environment
    }

    private static func resolveVersionViaShell(
        at path: String,
        environment: [String: String]
    ) -> String? {
        for shellPath in shellCandidates(from: environment) {
            guard testHooks.isExecutableFile(shellPath) else { continue }

            let shellArg0 = URL(fileURLWithPath: shellPath).lastPathComponent
            if let version = resolveVersion(
                executablePath: shellPath,
                arguments: ["-lc", "\"$1\" --version", shellArg0, path],
                environment: environment
            ) {
                return version
            }

            if let version = resolveVersion(
                executablePath: shellPath,
                arguments: ["-ic", "\"$1\" --version", shellArg0, path],
                environment: environment
            ) {
                return version
            }
        }

        return nil
    }

    private static func resolveVersion(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) -> String? {
        guard let output = testHooks.runProcess(executablePath, arguments, environment) else {
            return nil
        }

        return extractVersion(from: output)
    }
}

struct CodexHookInstaller {
    struct TestHooks {
        var bundledHookScriptURL: () -> URL?
    }

    static let hookScriptFileName = "nocline-codex-hook.sh"
    static let legacyHookScriptFileNames = ["notchi-codex-hook.sh"]
    static let hookCommand = "\"${CODEX_HOME:-$HOME/.codex}/hooks/nocline-codex-hook.sh\""
    static var testHooks = makeDefaultTestHooks()

    static func resetTestingHooks() {
        testHooks = makeDefaultTestHooks()
    }

    @discardableResult
    static func installIfAvailable() -> Bool {
        guard CodexCLIResolver.resolveExecutablePath() != nil else {
            codexLogger.info("Codex CLI executable not found")
            return false
        }

        return installIfNeeded()
    }

    @discardableResult
    static func installIfNeeded() -> Bool {
        let codexConfig = CodexConfigDirectoryResolver.resolve()
        guard let codexPath = CodexCLIResolver.resolveExecutablePath() else {
            codexLogger.info("Codex CLI executable not found")
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: codexConfig.hooksDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            codexLogger.error("Failed to create Codex hooks directory: \(error.localizedDescription)")
            return false
        }

        guard installHookScript(to: codexConfig.hookScriptURL) else {
            return false
        }

        let enabledFeature = CodexCLIResolver.enableHooksFeature(
            at: codexPath,
            codexHome: codexConfig.directoryURL.path
        )
        guard enabledFeature else {
            codexLogger.error("Failed to enable Codex hooks feature")
            return false
        }

        return updateHooksJSON(
            at: codexConfig.hooksJSONURL,
            command: hookCommand
        )
    }

    static func upsertHookSettings(from existingData: Data?, command: String) -> Data? {
        var json: [String: Any] = [:]
        if let existingData,
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let hookEvents: [(String, [[String: Any]])] = [
            ("SessionStart", [["matcher": "startup|resume|clear", "hooks": hookEntries(command: command)]]),
            ("UserPromptSubmit", [["hooks": hookEntries(command: command)]]),
            ("PreToolUse", [["matcher": "Bash", "hooks": hookEntries(command: command)]]),
            ("PermissionRequest", [["matcher": "Bash", "hooks": hookEntries(command: command)]]),
            ("PostToolUse", [["matcher": "Bash", "hooks": hookEntries(command: command)]]),
            ("Stop", [["hooks": hookEntries(command: command)]]),
        ]

        for (event, config) in hookEvents {
            hooks[event] = upsertEventHook(
                existingValue: hooks[event],
                config: config,
                command: command
            )
        }

        json["hooks"] = hooks

        return try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    static func isHookInstalled(in hooksData: Data?) -> Bool {
        guard let hooksData,
              let json = try? JSONSerialization.jsonObject(with: hooksData) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return entryHooks.contains { hook in
                    matchesManagedHookScript(in: hook["command"] as? String ?? "")
                }
            }
        }
    }

    static func isInstalled() -> Bool {
        let hooksJSON = CodexConfigDirectoryResolver.resolve().hooksJSONURL
        return isHookInstalled(in: try? Data(contentsOf: hooksJSON))
    }

    static func uninstall() {
        let codexConfig = CodexConfigDirectoryResolver.resolve()
        try? FileManager.default.removeItem(at: codexConfig.hookScriptURL)

        guard let data = try? Data(contentsOf: codexConfig.hooksJSONURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return matchesManagedHookScript(in: cmd)
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: codexConfig.hooksJSONURL)
        }

        codexLogger.info("Uninstalled Nocline Codex hooks")
    }

    private static func installHookScript(to hookScript: URL) -> Bool {
        guard let bundled = testHooks.bundledHookScriptURL() else {
            codexLogger.error("Codex hook script not found in bundle")
            return false
        }

        do {
            let bundledData = try Data(contentsOf: bundled)
            try bundledData.write(to: hookScript, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: hookScript.path
            )
            codexLogger.info("Installed Codex hook script to \(hookScript.path, privacy: .public)")
            return true
        } catch {
            codexLogger.error("Failed to install Codex hook script: \(error.localizedDescription)")
            return false
        }
    }

    private static func updateHooksJSON(at hooksURL: URL, command: String) -> Bool {
        let existingData = try? Data(contentsOf: hooksURL)
        guard let data = upsertHookSettings(from: existingData, command: command) else {
            codexLogger.error("Failed to serialize Codex hooks JSON")
            return false
        }

        do {
            try data.write(to: hooksURL)
            codexLogger.info("Updated hooks.json with Nocline Codex hooks")
            return true
        } catch {
            codexLogger.error("Failed to write Codex hooks.json: \(error.localizedDescription)")
            return false
        }
    }

    private static func upsertEventHook(
        existingValue: Any?,
        config: [[String: Any]],
        command: String
    ) -> [[String: Any]] {
        guard var existingEvent = existingValue as? [[String: Any]] else {
            return config
        }

        var insertionIndex: Int?

        for index in existingEvent.indices {
            guard var entryHooks = existingEvent[index]["hooks"] as? [[String: Any]] else { continue }

            var entryMatched = false
            entryHooks.removeAll { hook in
                let cmd = hook["command"] as? String ?? ""
                let isCurrent = cmd == command
                let isLegacy = matchesLegacyHookScript(in: cmd)
                if isCurrent || isLegacy {
                    entryMatched = true
                }
                return isCurrent || isLegacy
            }

            if entryMatched, insertionIndex == nil {
                insertionIndex = index
            }

            existingEvent[index]["hooks"] = entryHooks
        }

        if let insertionIndex {
            var entryHooks = existingEvent[insertionIndex]["hooks"] as? [[String: Any]] ?? []
            entryHooks.append(["type": "command", "command": command])
            existingEvent[insertionIndex]["hooks"] = entryHooks
            return existingEvent
        }

        existingEvent.append(contentsOf: config)
        return existingEvent
    }

    private static func hookEntries(command: String) -> [[String: Any]] {
        [["type": "command", "command": command]]
    }

    private static func matchesManagedHookScript(in command: String) -> Bool {
        if command.contains(hookScriptFileName) {
            return true
        }
        return matchesLegacyHookScript(in: command)
    }

    private static func matchesLegacyHookScript(in command: String) -> Bool {
        legacyHookScriptFileNames.contains { command.contains($0) }
    }

    private static func makeDefaultTestHooks() -> TestHooks {
        TestHooks(
            bundledHookScriptURL: {
                Bundle.main.url(forResource: "nocline-codex-hook", withExtension: "sh")
            }
        )
    }
}
