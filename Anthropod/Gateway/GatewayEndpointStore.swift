import Foundation

struct GatewayEndpoint: Sendable, Equatable {
    let url: URL
    let token: String?
    let password: String?
}

actor GatewayEndpointStore {
    static let shared = GatewayEndpointStore()

    private var cached: GatewayEndpoint?

    func resolve(fallbackHost: String, fallbackPort: Int) async -> GatewayEndpoint {
        if let cached { return cached }
        let endpoint = Self.buildEndpoint(
            env: ProcessInfo.processInfo.environment,
            fallbackHost: fallbackHost,
            fallbackPort: fallbackPort
        )
        cached = endpoint
        return endpoint
    }

    func refresh(fallbackHost: String, fallbackPort: Int) async -> GatewayEndpoint {
        let endpoint = Self.buildEndpoint(
            env: ProcessInfo.processInfo.environment,
            fallbackHost: fallbackHost,
            fallbackPort: fallbackPort
        )
        cached = endpoint
        return endpoint
    }

    private static func buildEndpoint(
        env: [String: String],
        fallbackHost: String,
        fallbackPort: Int
    ) -> GatewayEndpoint {
        let root = ClawdbotConfigFile.loadDict()
        let launchdSnapshot = GatewayLaunchAgent.snapshot()
        let mode = Self.trimmed((root["gateway"] as? [String: Any])?["mode"] as? String)
        let isRemote = mode == "remote"

        let token = Self.resolveGatewayToken(
            isRemote: isRemote,
            env: env,
            launchdSnapshot: launchdSnapshot
        )
        let password = Self.resolveGatewayPassword(
            isRemote: isRemote,
            env: env,
            launchdSnapshot: launchdSnapshot
        )

        if let rawUrl = Self.trimmed(env["CLAWDBOT_GATEWAY_URL"]) {
            let normalized = rawUrl.contains("://") ? rawUrl : "ws://\(rawUrl)"
            if let url = URL(string: normalized) {
                return GatewayEndpoint(url: url, token: token, password: password)
            }
        }

        if isRemote, let remoteUrl = ClawdbotConfigFile.gatewayRemoteURL() {
            return GatewayEndpoint(url: remoteUrl, token: token, password: password)
        }

        let scheme = Self.trimmed(env["CLAWDBOT_GATEWAY_SCHEME"]) ?? "ws"
        let host = Self.trimmed(env["CLAWDBOT_GATEWAY_HOST"]) ?? fallbackHost
        let port = Self.resolveGatewayPort(
            env: env,
            configPort: ClawdbotConfigFile.gatewayPort(),
            launchdPort: launchdSnapshot?.port,
            fallback: fallbackPort
        )
        let url = URL(string: "\(scheme)://\(host):\(port)")!

        return GatewayEndpoint(url: url, token: token, password: password)
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolveGatewayPort(
        env: [String: String],
        configPort: Int?,
        launchdPort: Int?,
        fallback: Int
    ) -> Int {
        if let raw = trimmed(env["CLAWDBOT_GATEWAY_PORT"]),
           let parsed = Int(raw),
           parsed > 0
        {
            return parsed
        }
        if let configPort, configPort > 0 { return configPort }
        if let launchdPort, launchdPort > 0 { return launchdPort }
        return fallback
    }

    private static func resolveGatewayToken(
        isRemote: Bool,
        env: [String: String],
        launchdSnapshot: LaunchAgentPlistSnapshot?
    ) -> String? {
        if let raw = trimmed(env["CLAWDBOT_GATEWAY_TOKEN"]) {
            return raw
        }
        if isRemote {
            if let token = ClawdbotConfigFile.gatewayRemoteToken(),
               !token.isEmpty
            {
                return token
            }
            return nil
        }
        if let token = ClawdbotConfigFile.gatewayAuthToken(),
           !token.isEmpty
        {
            return token
        }
        if let token = launchdSnapshot?.token?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            return token
        }
        return nil
    }

    private static func resolveGatewayPassword(
        isRemote: Bool,
        env: [String: String],
        launchdSnapshot: LaunchAgentPlistSnapshot?
    ) -> String? {
        if let raw = trimmed(env["CLAWDBOT_GATEWAY_PASSWORD"]) {
            return raw
        }
        if isRemote {
            if let password = ClawdbotConfigFile.gatewayRemotePassword(),
               !password.isEmpty
            {
                return password
            }
            return nil
        }
        if let password = ClawdbotConfigFile.gatewayAuthPassword(),
           !password.isEmpty
        {
            return password
        }
        if let password = launchdSnapshot?.password?.trimmingCharacters(in: .whitespacesAndNewlines),
           !password.isEmpty
        {
            return password
        }
        return nil
    }
}
