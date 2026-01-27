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

    var gatewayURL: URL {
        URL(string: "ws://\(gatewayHost):\(gatewayPort)")!
    }

    // MARK: - Private

    private var client: GatewayClient?
    private var eventHandlers: [(AgentRunEvent) -> Void] = []

    private init() {}

    // MARK: - Connection

    func connect() async {
        guard !isConnecting else { return }

        isConnecting = true
        connectionError = nil

        let newClient = GatewayClient(url: gatewayURL)
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

            logger.info("Connected to gateway at \(self.gatewayURL.absoluteString, privacy: .public)")
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
    func chatHistory(sessionKey: String? = nil, limit: Int = 100) async throws -> [ChatMessage] {
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

        let response: ChatSendResponse = try await client.requestDecoded(
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

        return response.runId ?? idempotencyKey
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

    // MARK: - Event Handling

    func onAgentRun(_ handler: @escaping (AgentRunEvent) -> Void) {
        eventHandlers.append(handler)
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
                if let agentEvent = AgentRunEvent(from: evt) {
                    for handler in self.eventHandlers {
                        handler(agentEvent)
                    }
                }

            case .seqGap:
                logger.warning("Sequence gap detected")
            }
        }
    }
}
