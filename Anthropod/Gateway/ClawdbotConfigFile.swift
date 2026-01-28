import Foundation
import OSLog

enum ClawdbotConfigFile {
    private static let logger = Logger(subsystem: "bot.molt.anthropod", category: "config")

    static func url() -> URL {
        ClawdbotPaths.configURL
    }

    static func loadDict() -> [String: Any] {
        let url = self.url()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            guard let root = self.parseConfigData(data) else {
                self.logger.warning("config JSON root invalid")
                return [:]
            }
            return root
        } catch {
            self.logger.warning("config read failed: \(error.localizedDescription)")
            return [:]
        }
    }

    static func gatewayPort() -> Int? {
        let root = self.loadDict()
        guard let gateway = root["gateway"] as? [String: Any] else { return nil }
        if let port = gateway["port"] as? Int, port > 0 { return port }
        if let number = gateway["port"] as? NSNumber, number.intValue > 0 {
            return number.intValue
        }
        if let raw = gateway["port"] as? String,
           let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           parsed > 0
        {
            return parsed
        }
        return nil
    }

    static func gatewayMode() -> String? {
        let root = self.loadDict()
        guard let gateway = root["gateway"] as? [String: Any],
              let mode = gateway["mode"] as? String
        else {
            return nil
        }
        let trimmed = mode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func gatewayAuthToken() -> String? {
        let root = self.loadDict()
        return Self.resolveGatewayToken(root: root, preferRemote: false)
    }

    static func gatewayAuthPassword() -> String? {
        let root = self.loadDict()
        return Self.resolveGatewayPassword(root: root, preferRemote: false)
    }

    static func gatewayRemoteToken() -> String? {
        let root = self.loadDict()
        return Self.resolveGatewayToken(root: root, preferRemote: true)
    }

    static func gatewayRemotePassword() -> String? {
        let root = self.loadDict()
        return Self.resolveGatewayPassword(root: root, preferRemote: true)
    }

    static func gatewayRemoteURL() -> URL? {
        let root = self.loadDict()
        guard let gateway = root["gateway"] as? [String: Any],
              let remote = gateway["remote"] as? [String: Any],
              let raw = remote["url"] as? String
        else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func resolveGatewayToken(root: [String: Any], preferRemote: Bool) -> String? {
        if preferRemote {
            if let gateway = root["gateway"] as? [String: Any],
               let remote = gateway["remote"] as? [String: Any],
               let token = remote["token"] as? String
            {
                return token.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            }
            return nil
        }
        if let gateway = root["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String
        {
            return token.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        return nil
    }

    private static func resolveGatewayPassword(root: [String: Any], preferRemote: Bool) -> String? {
        if preferRemote {
            if let gateway = root["gateway"] as? [String: Any],
               let remote = gateway["remote"] as? [String: Any],
               let password = remote["password"] as? String
            {
                return password.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            }
            return nil
        }
        if let gateway = root["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let password = auth["password"] as? String
        {
            return password.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        return nil
    }

    private static func parseConfigData(_ data: Data) -> [String: Any]? {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return root
        }
        let decoder = JSONDecoder()
        if #available(macOS 12.0, *) {
            decoder.allowsJSON5 = true
        }
        if let decoded = try? decoder.decode([String: AnyCodable].self, from: data) {
            self.logger.notice("config parsed with JSON5 decoder")
            return decoded.mapValues { $0.value }
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
