import Foundation

enum GatewayLaunchAgent {
    static let labels = [
        "bot.molt.gateway",
        "com.clawdbot.gateway",
    ]

    static func plistURL(label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func snapshot() -> LaunchAgentPlistSnapshot? {
        for label in labels {
            let url = plistURL(label: label)
            if let snapshot = LaunchAgentPlist.snapshot(url: url) {
                return snapshot
            }
        }
        return nil
    }
}
