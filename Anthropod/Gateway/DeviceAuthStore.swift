import Foundation

nonisolated struct DeviceAuthEntry: Codable, Sendable {
    let token: String
    let role: String
    let scopes: [String]
    let updatedAtMs: Int
}

nonisolated private struct DeviceAuthStoreFile: Codable {
    var version: Int
    var deviceId: String
    var tokens: [String: DeviceAuthEntry]
}

enum DeviceAuthStore {
    nonisolated private static let fileName = "device-auth.json"

    nonisolated static func loadToken(deviceId: String, role: String) -> DeviceAuthEntry? {
        guard let store = readStore(), store.deviceId == deviceId else { return nil }
        let role = normalizeRole(role)
        return store.tokens[role]
    }

    nonisolated static func storeToken(
        deviceId: String,
        role: String,
        token: String,
        scopes: [String] = []
    ) -> DeviceAuthEntry {
        let normalizedRole = normalizeRole(role)
        var next = readStore()
        if next?.deviceId != deviceId {
            next = DeviceAuthStoreFile(version: 1, deviceId: deviceId, tokens: [:])
        }
        let entry = DeviceAuthEntry(
            token: token,
            role: normalizedRole,
            scopes: normalizeScopes(scopes),
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
        if next == nil {
            next = DeviceAuthStoreFile(version: 1, deviceId: deviceId, tokens: [:])
        }
        next?.tokens[normalizedRole] = entry
        if let store = next {
            writeStore(store)
        }
        return entry
    }

    nonisolated static func clearToken(deviceId: String, role: String) {
        guard var store = readStore(), store.deviceId == deviceId else { return }
        let normalizedRole = normalizeRole(role)
        guard store.tokens[normalizedRole] != nil else { return }
        store.tokens.removeValue(forKey: normalizedRole)
        writeStore(store)
    }

    nonisolated private static func normalizeRole(_ role: String) -> String {
        role.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizeScopes(_ scopes: [String]) -> [String] {
        let trimmed = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(trimmed)).sorted()
    }

    nonisolated private static func fileURL() -> URL {
        DeviceIdentityPaths.stateDirURL()
            .appendingPathComponent("identity", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated private static func readStore() -> DeviceAuthStoreFile? {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(DeviceAuthStoreFile.self, from: data) else {
            return nil
        }
        guard decoded.version == 1 else { return nil }
        return decoded
    }

    nonisolated private static func writeStore(_ store: DeviceAuthStoreFile) {
        let url = fileURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(store)
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // best-effort only
        }
    }
}
