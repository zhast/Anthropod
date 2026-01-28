//
//  GatewayService.swift
//  Anthropod
//
//  Shared gateway service for the app
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "bot.molt.anthropod", category: "gateway.service")

/// Shared gateway service singleton
@MainActor
@Observable
final class GatewayService {
    static let shared = GatewayService()

    // MARK: - State

    var isConnected = false
    var isConnecting = false
    var connectionError: String?
    var mainSessionKey: String = "main"

    // MARK: - Configuration

    var gatewayHost: String = "127.0.0.1"
    var gatewayPort: Int = 18789

    // MARK: - Private

    private var client: GatewayClient?
    private var agentRunHandlers: [(AgentRunEvent) -> Void] = []
    private var chatHandlers: [(ChatRunEvent) -> Void] = []
    private var agentHandlers: [(AgentStreamEvent) -> Void] = []

    private init() {}

    // MARK: - Connection

    func connect() async {
        guard !isConnecting else { return }

        isConnecting = true
        connectionError = nil

        let endpoint = await GatewayEndpointStore.shared.resolve(
            fallbackHost: gatewayHost,
            fallbackPort: gatewayPort
        )
        let ready = await GatewayProcessManager.shared.ensureGatewayRunning(endpoint: endpoint)
        if !ready {
            connectionError = "Gateway did not become ready"
            isConnected = false
            isConnecting = false
            return
        }

        let newClient = GatewayClient(url: endpoint.url, token: endpoint.token, password: endpoint.password)
        await newClient.setPushHandler { [weak self] push in
            await self?.handlePush(push)
        }

        do {
            try await newClient.connect()
            client = newClient
            isConnected = true

            if let sessionKey = await newClient.getMainSessionKey() {
                mainSessionKey = sessionKey
            }

            logger.info("Connected to gateway at \(endpoint.url.absoluteString, privacy: .public)")
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
            logger.error("Failed to connect: \(error.localizedDescription, privacy: .public)")
        }

        isConnecting = false
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        isConnected = false
    }

    // MARK: - Chat API

    /// Fetch chat history for a session
    func chatHistory(sessionKey: String? = nil, limit: Int = 200) async throws -> [GatewayChatHistoryMessage] {
        guard let client else { throw GatewayError.notConnected }

        let key = sessionKey ?? mainSessionKey
        let payload: ChatHistoryPayload = try await client.requestDecoded(
            method: "chat.history",
            params: ["sessionKey": key, "limit": limit]
        )
        return payload.messages
    }

    /// Send a chat message
    func chatSend(
        message: String,
        sessionKey: String? = nil,
        thinking: String = "default"
    ) async throws -> String {
        guard let client else { throw GatewayError.notConnected }

        let key = sessionKey ?? mainSessionKey
        let idempotencyKey = UUID().uuidString

        let response: ChatSendResponse? = try await client.requestDecodedOptional(
            method: "chat.send",
            params: [
                "sessionKey": key,
                "message": message,
                "thinking": thinking,
                "idempotencyKey": idempotencyKey,
                "timeoutMs": 30000
            ],
            timeoutMs: 35000
        )

        return response?.runId ?? idempotencyKey
    }

    /// Abort an in-progress chat
    func chatAbort(sessionKey: String? = nil, runId: String) async throws -> Bool {
        guard let client else { throw GatewayError.notConnected }

        let key = sessionKey ?? mainSessionKey

        struct AbortResponse: Decodable {
            let ok: Bool?
            let aborted: Bool?
        }

        let response: AbortResponse = try await client.requestDecoded(
            method: "chat.abort",
            params: ["sessionKey": key, "runId": runId]
        )

        return response.aborted ?? false
    }

    // MARK: - Models & Usage

    func modelsList() async throws -> [ModelChoice] {
        guard let client else { throw GatewayError.notConnected }
        let payload: ModelsListResult = try await client.requestDecoded(
            method: "models.list",
            params: nil,
            timeoutMs: 7000
        )
        return payload.models
    }

    struct SessionModelSnapshot: Sendable {
        let defaultProvider: String?
        let defaultModel: String?
        let defaultContextTokens: Int?
        let sessionProvider: String?
        let sessionModel: String?
        let sessionContextTokens: Int?
    }

    func sessionModelSnapshot(sessionKey: String? = nil) async throws -> SessionModelSnapshot {
        guard let client else { throw GatewayError.notConnected }
        let key = sessionKey ?? mainSessionKey
        let params: [String: Any] = [
            "search": key,
            "limit": 20,
            "includeGlobal": true,
            "includeUnknown": true
        ]
        let payload: SessionsListResult = try await client.requestDecoded(
            method: "sessions.list",
            params: params,
            timeoutMs: 7000
        )
        let match = payload.sessions.first { $0.key == key }
        return SessionModelSnapshot(
            defaultProvider: payload.defaults.modelProvider,
            defaultModel: payload.defaults.model,
            defaultContextTokens: payload.defaults.contextTokens,
            sessionProvider: match?.modelProvider,
            sessionModel: match?.model,
            sessionContextTokens: match?.contextTokens
        )
    }

    func usageCostSummary() async throws -> GatewayCostUsageSummary {
        guard let client else { throw GatewayError.notConnected }
        return try await client.requestDecoded(
            method: "usage.cost",
            params: nil,
            timeoutMs: 7000
        )
    }

    func patchSessionModel(sessionKey: String? = nil, modelId: String?) async throws {
        guard let client else { throw GatewayError.notConnected }
        let key = sessionKey ?? mainSessionKey
        var params: [String: Any] = ["key": key]
        if let modelId, !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["model"] = modelId
        } else {
            params["model"] = NSNull()
        }
        _ = try await client.request(method: "sessions.patch", params: params, timeoutMs: 7000)
    }

    func compactSession(sessionKey: String? = nil, maxLines: Int = 400) async throws {
        guard let client else { throw GatewayError.notConnected }
        let key = sessionKey ?? mainSessionKey
        _ = try await client.request(
            method: "sessions.compact",
            params: ["key": key, "maxLines": maxLines],
            timeoutMs: 15000
        )
    }

    // MARK: - Event Handling

    func onAgentRun(_ handler: @escaping (AgentRunEvent) -> Void) {
        agentRunHandlers.append(handler)
    }

    func onChatEvent(_ handler: @escaping (ChatRunEvent) -> Void) {
        chatHandlers.append(handler)
    }

    func onAgentEvent(_ handler: @escaping (AgentStreamEvent) -> Void) {
        agentHandlers.append(handler)
    }

    private func handlePush(_ push: GatewayPush) async {
        await MainActor.run {
            switch push {
            case let .snapshot(hello):
                self.isConnected = true
                if let defaults = hello.snapshot.sessionDefaults,
                   let key = defaults["mainSessionKey"]?.value as? String {
                    self.mainSessionKey = key
                }

            case let .event(evt):
                if let agentRun = AgentRunEvent(from: evt) {
                    for handler in self.agentRunHandlers {
                        handler(agentRun)
                    }
                    return
                }
                if let chatEvent = ChatRunEvent(from: evt) {
                    for handler in self.chatHandlers {
                        handler(chatEvent)
                    }
                    return
                }
                if let agentEvent = AgentStreamEvent(from: evt) {
                    for handler in self.agentHandlers {
                        handler(agentEvent)
                    }
                    return
                }

            case .seqGap:
                logger.warning("Sequence gap detected")
            }
        }
    }

    // MARK: - Debug Report

    func debugReport() async -> String {
        let endpoint = await GatewayEndpointStore.shared.resolve(
            fallbackHost: gatewayHost,
            fallbackPort: gatewayPort
        )
        let processManager = GatewayProcessManager.shared
        let env = ProcessInfo.processInfo.environment
        let configPath = ClawdbotConfigFile.url().path
        let launchdSnapshot = GatewayLaunchAgent.snapshot()

        let now = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []
        lines.append("timestamp: \(now)")
        lines.append("endpoint.url: \(endpoint.url.absoluteString)")
        lines.append("endpoint.token: \(redact(endpoint.token))")
        lines.append("endpoint.password: \(redact(endpoint.password))")
        lines.append("config.path: \(configPath)")
        lines.append("config.gateway.mode: \(ClawdbotConfigFile.gatewayMode() ?? "n/a")")
        lines.append("config.gateway.port: \(ClawdbotConfigFile.gatewayPort().map(String.init) ?? "n/a")")
        lines.append("config.gateway.auth.token: \(redact(ClawdbotConfigFile.gatewayAuthToken()))")
        lines.append("config.gateway.auth.password: \(redact(ClawdbotConfigFile.gatewayAuthPassword()))")
        lines.append("launchd.gateway.port: \(launchdSnapshot?.port.map(String.init) ?? "n/a")")
        lines.append("launchd.gateway.token: \(redact(launchdSnapshot?.token))")
        lines.append("launchd.gateway.password: \(redact(launchdSnapshot?.password))")
        lines.append("gateway.status: \(processManager.status.label)")
        lines.append("gateway.command: \(processManager.lastCommandDescription ?? "n/a")")
        lines.append("gateway.lastProbe: \(processManager.lastProbe ?? "n/a")")
        lines.append("gateway.startError: \(processManager.lastStartError ?? "n/a")")
        lines.append("gateway.readyError: \(processManager.lastReadyError ?? "n/a")")
        lines.append("state.isConnected: \(isConnected)")
        lines.append("state.isConnecting: \(isConnecting)")
        lines.append("state.error: \(connectionError ?? "n/a")")
        lines.append("env.CLAWDBOT_GATEWAY_URL: \(envValue(env, key: "CLAWDBOT_GATEWAY_URL"))")
        lines.append("env.CLAWDBOT_GATEWAY_HOST: \(envValue(env, key: "CLAWDBOT_GATEWAY_HOST"))")
        lines.append("env.CLAWDBOT_GATEWAY_PORT: \(envValue(env, key: "CLAWDBOT_GATEWAY_PORT"))")
        lines.append("env.CLAWDBOT_GATEWAY_SCHEME: \(envValue(env, key: "CLAWDBOT_GATEWAY_SCHEME"))")
        lines.append("env.CLAWDBOT_GATEWAY_TOKEN: \(redact(env["CLAWDBOT_GATEWAY_TOKEN"]))")
        lines.append("env.CLAWDBOT_GATEWAY_PASSWORD: \(redact(env["CLAWDBOT_GATEWAY_PASSWORD"]))")
        lines.append("env.ANTHROPOD_GATEWAY_COMMAND: \(envValue(env, key: "ANTHROPOD_GATEWAY_COMMAND"))")
        lines.append("env.ANTHROPOD_GATEWAY_ARGS: \(envValue(env, key: "ANTHROPOD_GATEWAY_ARGS"))")
        lines.append("env.ANTHROPOD_GATEWAY_CWD: \(envValue(env, key: "ANTHROPOD_GATEWAY_CWD"))")
        lines.append("env.ANTHROPOD_MOLTBOT_ROOT: \(envValue(env, key: "ANTHROPOD_MOLTBOT_ROOT"))")
        if let client {
            let trace = await client.traceSnapshot()
            if !trace.isEmpty {
                lines.append("trace.enabled: true")
                lines.append("trace.tail:")
                lines.append(trace)
            } else {
                lines.append("trace.enabled: false")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func redact(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "n/a"
        }
        if trimmed.count <= 8 {
            return "****"
        }
        let prefix = trimmed.prefix(3)
        let suffix = trimmed.suffix(3)
        return "\(prefix)…\(suffix)"
    }

    private func envValue(_ env: [String: String], key: String) -> String {
        let raw = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "n/a" : raw
    }
}
