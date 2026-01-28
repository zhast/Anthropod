import Foundation

enum GatewayLaunchAgent {
    nonisolated static let labels = [
        "bot.molt.gateway",
        "com.clawdbot.gateway",
    ]

    nonisolated static func plistURL(label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    nonisolated static func snapshot() -> LaunchAgentPlistSnapshot? {
        for label in labels {
            let url = plistURL(label: label)
            if let snapshot = LaunchAgentPlist.snapshot(url: url) {
                return snapshot
            }
        }
        return nil
    }
}
