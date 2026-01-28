import Foundation

enum InstanceIdentity {
    nonisolated private static let suiteName = "bot.molt.shared"
    nonisolated private static let legacySuiteName = "com.clawdbot.shared"
    nonisolated private static let instanceIdKey = "instanceId"

    nonisolated private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    nonisolated private static var legacyDefaults: UserDefaults? {
        UserDefaults(suiteName: legacySuiteName)
    }

    nonisolated static let instanceId: String = {
        let defaults = Self.defaults
        if let existing = defaults.string(forKey: instanceIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty {
            return existing
        }

        if let legacy = Self.legacyDefaults?.string(forKey: instanceIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty {
            defaults.set(legacy, forKey: instanceIdKey)
            return legacy
        }

        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: instanceIdKey)
        return id
    }()

    nonisolated static let displayName: String = {
        if let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "moltbot"
    }()

    nonisolated static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let raw = String(bytes: bytes, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }()

    nonisolated static let deviceFamily: String = { "Mac" }()

    nonisolated static let platformString: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
}
