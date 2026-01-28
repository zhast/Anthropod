import Foundation

enum ClawdbotEnv {
    nonisolated static func path(_ key: String) -> String? {
        guard let raw = getenv(key) else { return nil }
        let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum ClawdbotPaths {
    nonisolated private static let configPathEnv = "CLAWDBOT_CONFIG_PATH"
    nonisolated private static let stateDirEnv = "CLAWDBOT_STATE_DIR"

    nonisolated static var stateDirURL: URL {
        if let override = ClawdbotEnv.path(self.stateDirEnv) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clawdbot", isDirectory: true)
    }

    nonisolated static var configURL: URL {
        if let override = ClawdbotEnv.path(self.configPathEnv) {
            return URL(fileURLWithPath: override)
        }
        let stateDir = self.stateDirURL
        let moltbot = stateDir.appendingPathComponent("moltbot.json")
        if FileManager.default.fileExists(atPath: moltbot.path) {
            return moltbot
        }
        let clawdbot = stateDir.appendingPathComponent("clawdbot.json")
        if FileManager.default.fileExists(atPath: clawdbot.path) {
            return clawdbot
        }
        return moltbot
    }

    nonisolated static var agentsURL: URL {
        stateDirURL.appendingPathComponent("agents.md")
    }
}
