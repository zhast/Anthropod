//
//  GatewayClient.swift
//  Anthropod
//
//  WebSocket client for Moltbot gateway communication
//

import Foundation
import OSLog

/// Gateway WebSocket client actor
actor GatewayClient {
    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<GatewayFrame, Error>] = [:]
    private var connected = false
    private var isConnecting = false
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []

    private let url: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let connectTimeoutSeconds: Double = 6
    private let defaultRequestTimeoutMs: Double = 15000

    private var pushHandler: (@Sendable (GatewayPush) async -> Void)?
    private var lastSnapshot: HelloOk?
    private var tickIntervalMs: Double = 30000

    // MARK: - Initialization

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    // MARK: - Configuration

    func setPushHandler(_ handler: @escaping @Sendable (GatewayPush) async -> Void) {
        self.pushHandler = handler
    }

    func getMainSessionKey() -> String? {
        guard let defaults = lastSnapshot?.snapshot.sessionDefaults else { return nil }
        return defaults["mainSessionKey"]?.value as? String
    }

    // MARK: - Connection

    func connect() async throws {
        if connected, task?.state == .running { return }

        if isConnecting {
            try await withCheckedThrowingContinuation { cont in
                connectWaiters.append(cont)
            }
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        task?.cancel(with: .goingAway, reason: nil)
        task = session.webSocketTask(with: url)
        task?.maximumMessageSize = 16 * 1024 * 1024 // 16 MB
        task?.resume()

        do {
            try await withTimeout(seconds: connectTimeoutSeconds) {
                try await self.sendConnect()
            }
        } catch {
            connected = false
            task?.cancel(with: .goingAway, reason: nil)

            let waiters = connectWaiters
            connectWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(throwing: error)
            }
            throw error
        }

        listen()
        connected = true

        let waiters = connectWaiters
        connectWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: ())
        }
    }

    func disconnect() async {
        connected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        let waiters = pending
        pending.removeAll()
        for (_, waiter) in waiters {
            waiter.resume(throwing: GatewayError.disconnected)
        }
    }

    // MARK: - Requests

    func request(
        method: String,
        params: [String: Any]? = nil,
        timeoutMs: Double? = nil
    ) async throws -> Data {
        if !connected {
            try await connect()
        }

        let effectiveTimeout = timeoutMs ?? defaultRequestTimeoutMs
        let reqId = UUID().uuidString

        let paramsAny: AnyCodable? = params.map { AnyCodable($0) }
        let frame = RequestFrame(id: reqId, method: method, params: paramsAny)
        let data = try encoder.encode(frame)

        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GatewayFrame, Error>) in
            pending[reqId] = cont

            Task {
                try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000))
                await self.timeoutRequest(id: reqId, timeoutMs: effectiveTimeout)
            }

            Task {
                do {
                    try await self.task?.send(.data(data))
                } catch {
                    let waiter = self.pending.removeValue(forKey: reqId)
                    waiter?.resume(throwing: GatewayError.sendFailed(error.localizedDescription))
                }
            }
        }

        guard case let .res(res) = response else {
            throw GatewayError.unexpectedFrame
        }

        if res.ok == false {
            let code = res.error?["code"]?.value as? String
            let message = res.error?["message"]?.value as? String ?? "Unknown error"
            throw GatewayError.requestFailed(code: code, message: message)
        }

        if let payload = res.payload {
            return try encoder.encode(payload)
        }
        return Data()
    }

    func requestDecoded<T: Decodable>(
        method: String,
        params: [String: Any]? = nil,
        timeoutMs: Double? = nil
    ) async throws -> T {
        let data = try await request(method: method, params: params, timeoutMs: timeoutMs)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Private: Connect handshake

    private func sendConnect() async throws {
        let reqId = UUID().uuidString
        let platform = "darwin"
        let locale = Locale.preferredLanguages.first ?? Locale.current.identifier

        let client: [String: Any] = [
            "id": "anthropod-macos",
            "displayName": Host.current().localizedName ?? "Anthropod",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "platform": platform,
            "mode": "ui",
            "instanceId": UUID().uuidString
        ]

        let params: [String: Any] = [
            "minProtocol": GATEWAY_PROTOCOL_VERSION,
            "maxProtocol": GATEWAY_PROTOCOL_VERSION,
            "client": client,
            "caps": [] as [String],
            "locale": locale,
            "userAgent": ProcessInfo.processInfo.operatingSystemVersionString,
            "role": "operator",
            "scopes": ["operator.admin", "operator.approvals"]
        ]

        let frame = RequestFrame(id: reqId, method: "connect", params: AnyCodable(params))
        let data = try encoder.encode(frame)
        try await task?.send(.data(data))

        let response = try await waitForConnectResponse(reqId: reqId)
        try handleConnectResponse(response)
    }

    private func waitForConnectResponse(reqId: String) async throws -> ResponseFrame {
        guard let task else {
            throw GatewayError.notConnected
        }

        while true {
            let msg = try await task.receive()
            guard let data = decodeMessageData(msg) else { continue }
            guard let frame = try? decoder.decode(GatewayFrame.self, from: data) else { continue }

            if case let .res(res) = frame, res.id == reqId {
                return res
            }
        }
    }

    private func handleConnectResponse(_ res: ResponseFrame) throws {
        if res.ok == false {
            let msg = res.error?["message"]?.value as? String ?? "Connect failed"
            throw GatewayError.connectFailed(msg)
        }

        guard let payload = res.payload else {
            throw GatewayError.connectFailed("Missing payload")
        }

        let payloadData = try encoder.encode(payload)
        let hello = try decoder.decode(HelloOk.self, from: payloadData)

        if let tick = hello.policy["tickIntervalMs"]?.value as? Double {
            tickIntervalMs = tick
        } else if let tick = hello.policy["tickIntervalMs"]?.value as? Int {
            tickIntervalMs = Double(tick)
        }

        lastSnapshot = hello

        Task {
            await pushHandler?(.snapshot(hello))
        }
    }

    // MARK: - Private: Message handling

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                Task { await self.handleReceiveFailure(error) }
            case let .success(msg):
                Task {
                    await self.handleMessage(msg)
                    await self.listen()
                }
            }
        }
    }

    private func handleMessage(_ msg: URLSessionWebSocketTask.Message) async {
        guard let data = decodeMessageData(msg) else { return }
        guard let frame = try? decoder.decode(GatewayFrame.self, from: data) else {
            return
        }

        switch frame {
        case let .res(res):
            if let waiter = pending.removeValue(forKey: res.id) {
                waiter.resume(returning: .res(res))
            }
        case let .event(evt):
            if evt.event == "connect.challenge" { return }
            await pushHandler?(.event(evt))
        default:
            break
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        connected = false

        let waiters = pending
        pending.removeAll()
        for (_, waiter) in waiters {
            waiter.resume(throwing: GatewayError.disconnected)
        }
    }

    private nonisolated func decodeMessageData(_ msg: URLSessionWebSocketTask.Message) -> Data? {
        switch msg {
        case let .data(data): return data
        case let .string(text): return text.data(using: .utf8)
        @unknown default: return nil
        }
    }

    private func timeoutRequest(id: String, timeoutMs: Double) async {
        guard let waiter = pending.removeValue(forKey: id) else { return }
        waiter.resume(throwing: GatewayError.timeout(ms: Int(timeoutMs)))
    }

    // MARK: - Private: Timeout helper

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw GatewayError.timeout(ms: Int(seconds * 1000))
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Gateway Errors

enum GatewayError: LocalizedError {
    case notConnected
    case connectFailed(String)
    case disconnected
    case timeout(ms: Int)
    case sendFailed(String)
    case requestFailed(code: String?, message: String)
    case unexpectedFrame
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to gateway"
        case let .connectFailed(msg):
            return "Connect failed: \(msg)"
        case .disconnected:
            return "Disconnected from gateway"
        case let .timeout(ms):
            return "Request timed out after \(ms)ms"
        case let .sendFailed(msg):
            return "Send failed: \(msg)"
        case let .requestFailed(code, message):
            if let code {
                return "Request failed [\(code)]: \(message)"
            }
            return "Request failed: \(message)"
        case .unexpectedFrame:
            return "Unexpected response frame"
        case let .decodingFailed(msg):
            return "Decoding failed: \(msg)"
        }
    }
}
