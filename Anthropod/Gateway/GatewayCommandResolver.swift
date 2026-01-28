import Foundation

struct GatewayCommand {
    let executable: String
    let arguments: [String]
    let workingDirectory: String?
    let environment: [String: String]
}

enum GatewayCommandResolver {
    private static let helperNames = ["clawdbot", "moltbot"]

    static func resolveGatewayCommand(port: Int) -> GatewayCommand? {
        let env = ProcessInfo.processInfo.environment
        if let raw = trimmed(env["ANTHROPOD_GATEWAY_COMMAND"]) {
            let args = env["ANTHROPOD_GATEWAY_ARGS"]?
                .split(separator: " ")
                .map { String($0) } ?? []
            let cwd = trimmed(env["ANTHROPOD_GATEWAY_CWD"])
            return GatewayCommand(
                executable: raw,
                arguments: args,
                workingDirectory: cwd,
                environment: enrichedEnvironment())
        }

        let projectRoot = resolveProjectRoot()
        let searchPaths = preferredPaths(projectRoot: projectRoot)

        if let node = findExecutable(named: "node", searchPaths: searchPaths),
           let entry = gatewayEntrypoint(in: projectRoot) {
            return GatewayCommand(
                executable: node,
                arguments: [entry, "gateway-daemon", "--port", "\(port)", "--bind", "loopback"],
                workingDirectory: projectRoot?.path,
                environment: enrichedEnvironment(searchPaths: searchPaths))
        }

        if let pnpm = findExecutable(named: "pnpm", searchPaths: searchPaths) {
            return GatewayCommand(
                executable: pnpm,
                arguments: ["--silent", "moltbot", "gateway-daemon", "--port", "\(port)", "--bind", "loopback"],
                workingDirectory: projectRoot?.path,
                environment: enrichedEnvironment(searchPaths: searchPaths))
        }

        for name in helperNames {
            if let helper = findExecutable(named: name, searchPaths: searchPaths) {
                return GatewayCommand(
                    executable: helper,
                    arguments: ["gateway-daemon", "--port", "\(port)", "--bind", "loopback"],
                    workingDirectory: projectRoot?.path,
                    environment: enrichedEnvironment(searchPaths: searchPaths))
            }
        }

        return nil
    }

    private static func gatewayEntrypoint(in root: URL?) -> String? {
        guard let root else { return nil }
        let distEntry = root.appendingPathComponent("dist/index.js").path
        if FileManager().isReadableFile(atPath: distEntry) { return distEntry }
        let binEntry = root.appendingPathComponent("bin/moltbot.js").path
        if FileManager().isReadableFile(atPath: binEntry) { return binEntry }
        return nil
    }

    private static func resolveProjectRoot() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let raw = trimmed(env["ANTHROPOD_MOLTBOT_ROOT"]) {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        if let raw = trimmed(env["CLAWDBOT_PROJECT_ROOT"]) {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates: [URL] = [
            cwd.appendingPathComponent("moltbot", isDirectory: true),
            cwd.deletingLastPathComponent().appendingPathComponent("moltbot", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/GitHub/moltbot", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Projects/moltbot", isDirectory: true),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func preferredPaths(projectRoot: URL?) -> [String] {
        let current = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map(String.init) ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser
        var extras = [
            home.appendingPathComponent("Library/pnpm").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        if let projectRoot {
            extras.insert(projectRoot.appendingPathComponent("node_modules/.bin").path, at: 0)
        }
        var seen = Set<String>()
        return (extras + current).filter { seen.insert($0).inserted }
    }

    private static func findExecutable(named name: String, searchPaths: [String]) -> String? {
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager().isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func enrichedEnvironment(searchPaths: [String]? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let searchPaths {
            let joined = searchPaths.joined(separator: ":")
            env["PATH"] = joined
        }
        return env
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
