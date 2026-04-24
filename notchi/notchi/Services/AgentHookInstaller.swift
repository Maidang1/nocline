import Foundation
import os.log

private let agentHookLogger = Logger(subsystem: "com.ruban.notchi", category: "AgentHookInstaller")

struct AgentHookInstaller {
    @discardableResult
    static func installIfNeeded() -> Bool {
        uninstallLegacyClaudeHooksIfPresent()
        return CodexHookInstaller.installIfAvailable()
    }

    static func isAnyInstalled() -> Bool {
        CodexHookInstaller.isInstalled()
    }

    static func uninstallLegacyClaudeHooksIfPresent() {
        let configDirectoryURL = claudeConfigDirectoryURL()
        let settingsURL = configDirectoryURL.appendingPathComponent("settings.json")
        let hookScriptURL = configDirectoryURL
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("notchi-hook.sh")

        try? FileManager.default.removeItem(at: hookScriptURL)

        guard let existingData = try? Data(contentsOf: settingsURL),
              var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }

            let updatedEntries = entries.compactMap { entry -> [String: Any]? in
                guard let entryHooks = entry["hooks"] as? [[String: Any]] else {
                    return entry
                }

                let filteredHooks = entryHooks.filter { hook in
                    let command = hook["command"] as? String ?? ""
                    return !command.contains("notchi-hook.sh")
                }

                guard !filteredHooks.isEmpty else { return nil }

                var updatedEntry = entry
                updatedEntry["hooks"] = filteredHooks
                return updatedEntry
            }

            if updatedEntries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = updatedEntries
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        guard let updatedData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }

        do {
            try updatedData.write(to: settingsURL, options: .atomic)
            agentHookLogger.info("Removed legacy Claude hook registrations from \(settingsURL.path, privacy: .public)")
        } catch {
            agentHookLogger.error("Failed to remove legacy Claude hooks: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func claudeConfigDirectoryURL() -> URL {
        let environmentPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentPath, !environmentPath.isEmpty {
            return URL(fileURLWithPath: (environmentPath as NSString).expandingTildeInPath, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }
}
