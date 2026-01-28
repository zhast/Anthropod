import Foundation

enum ClawdbotEnv {
    nonisolated static func path(_ key: String) -> String? {
        guard let raw = getenv(key) else { return nil }
        let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated static func path(firstOf keys: [String]) -> String? {
        for key in keys {
            if let value = path(key) {
                return value
            }
        }
        return nil
    }
}

enum ClawdbotPaths {
    nonisolated private static let configPathEnv = ["MOLTBOT_CONFIG_PATH", "CLAWDBOT_CONFIG_PATH"]
    nonisolated private static let stateDirEnv = ["MOLTBOT_STATE_DIR", "CLAWDBOT_STATE_DIR"]
    nonisolated private static let newStateDirName = ".moltbot"
    nonisolated private static let legacyStateDirName = ".clawdbot"
    nonisolated private static let configFilename = "moltbot.json"
    nonisolated private static let legacyConfigFilename = "clawdbot.json"

    nonisolated static var stateDirURL: URL {
        if let override = ClawdbotEnv.path(firstOf: self.stateDirEnv) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacy = home.appendingPathComponent(legacyStateDirName, isDirectory: true)
        let modern = home.appendingPathComponent(newStateDirName, isDirectory: true)
        let hasLegacy = FileManager.default.fileExists(atPath: legacy.path)
        let hasModern = FileManager.default.fileExists(atPath: modern.path)
        if !hasLegacy && hasModern {
            return modern
        }
        return legacy
    }

    nonisolated static var configURL: URL {
        if let override = ClawdbotEnv.path(firstOf: self.configPathEnv) {
            return URL(fileURLWithPath: override)
        }
        if let existing = configCandidates().first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }
        let stateDir = self.stateDirURL
        return stateDir.appendingPathComponent(configFilename)
    }

    nonisolated static var agentsURL: URL {
        stateDirURL.appendingPathComponent("agents.md")
    }

    nonisolated private static func configCandidates() -> [URL] {
        var candidates: [URL] = []

        if let override = ClawdbotEnv.path("MOLTBOT_STATE_DIR") {
            candidates.append(contentsOf: configCandidates(in: URL(fileURLWithPath: override, isDirectory: true)))
        }
        if let override = ClawdbotEnv.path("CLAWDBOT_STATE_DIR") {
            candidates.append(contentsOf: configCandidates(in: URL(fileURLWithPath: override, isDirectory: true)))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(contentsOf: configCandidates(in: home.appendingPathComponent(newStateDirName, isDirectory: true)))
        candidates.append(contentsOf: configCandidates(in: home.appendingPathComponent(legacyStateDirName, isDirectory: true)))
        return candidates
    }

    nonisolated private static func configCandidates(in stateDir: URL) -> [URL] {
        [
            stateDir.appendingPathComponent(configFilename),
            stateDir.appendingPathComponent(legacyConfigFilename)
        ]
    }
}
