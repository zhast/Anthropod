import Foundation

struct LaunchAgentPlistSnapshot: Equatable, Sendable {
    let programArguments: [String]
    let environment: [String: String]
    let stdoutPath: String?
    let stderrPath: String?
    let port: Int?
    let bind: String?
    let token: String?
    let password: String?
}

enum LaunchAgentPlist {
    static func snapshot(url: URL) -> LaunchAgentPlistSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let rootAny: Any
        do {
            rootAny = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil)
        } catch {
            return nil
        }
        guard let root = rootAny as? [String: Any] else { return nil }
        let programArguments = root["ProgramArguments"] as? [String] ?? []
        let env = root["EnvironmentVariables"] as? [String: String] ?? [:]
        let stdoutPath = (root["StandardOutPath"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let stderrPath = (root["StandardErrorPath"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let port = Self.extractFlagInt(programArguments, flag: "--port")
        let bind = Self.extractFlagString(programArguments, flag: "--bind")?.lowercased()
        let token = env["CLAWDBOT_GATEWAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let password = env["CLAWDBOT_GATEWAY_PASSWORD"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        return LaunchAgentPlistSnapshot(
            programArguments: programArguments,
            environment: env,
            stdoutPath: stdoutPath,
            stderrPath: stderrPath,
            port: port,
            bind: bind,
            token: token,
            password: password
        )
    }

    private static func extractFlagInt(_ args: [String], flag: String) -> Int? {
        guard let raw = self.extractFlagString(args, flag: flag) else { return nil }
        return Int(raw)
    }

    private static func extractFlagString(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let valueIdx = args.index(after: idx)
        guard valueIdx < args.endIndex else { return nil }
        let token = args[valueIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
