import Foundation
import LocalAuthentication
import Security

enum KeychainManager {
    private static let claudeCodeService = "Claude Code-credentials"

    static func getAccessToken() -> String? {
        extractAccessToken(from: readClaudeCodeCredentials(allowInteraction: true))
    }

    static func getAccessTokenSilently() -> String? {
        extractAccessToken(from: readClaudeCodeCredentials(allowInteraction: false))
    }

    private static func extractAccessToken(from json: [String: Any]?) -> String? {
        guard let json,
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    }

    private static func readClaudeCodeCredentials(allowInteraction: Bool) -> [String: Any]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }
}
