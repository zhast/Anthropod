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
    private let token: String?
    private let password: String?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let connectTimeoutSeconds: Double = 6
    private let connectChallengeTimeoutSeconds: Double = 0.75
    private let defaultRequestTimeoutMs: Double = 15000

    private var pushHandler: (@Sendable (GatewayPush) async -> Void)?
    private var lastSnapshot: HelloOk?
    private var tickIntervalMs: Double = 30000
    private let traceEnabled: Bool
    private var traceLines: [String] = []
    private let traceLimit = 200

    // MARK: - Initialization

    init(
        url: URL,
        session: URLSession = .shared,
        token: String? = nil,
        password: String? = nil
    ) {
        self.url = url
        self.session = session
        self.token = token
        self.password = password
        let env = ProcessInfo.processInfo.environment
        self.traceEnabled = (env["ANTHROPOD_GATEWAY_TRACE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    // MARK: - Configuration

    func setPushHandler(_ handler: @escaping @Sendable (GatewayPush) async -> Void) {
        self.pushHandler = handler
    }

    func traceSnapshot() -> String {
        traceLines.joined(separator: "\n")
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

        let clientIds = preferredClientIds()
        await trace("connect: url=\(url.absoluteString) clients=\(clientIds.joined(separator: ","))")
        var lastError: Error?

        for (index, clientId) in clientIds.enumerated() {
            task?.cancel(with: .goingAway, reason: nil)
            task = session.webSocketTask(with: url)
            task?.maximumMessageSize = 16 * 1024 * 1024 // 16 MB
            task?.resume()

            do {
                try await withTimeout(seconds: connectTimeoutSeconds) {
                    try await self.sendConnect(clientId: clientId)
                }
                listen()
                connected = true
                await trace("connect: ok clientId=\(clientId)")

                let waiters = connectWaiters
                connectWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume(returning: ())
                }
                return
            } catch {
                lastError = error
                connected = false
                await trace("connect: failed clientId=\(clientId) error=\(error.localizedDescription)")
                task?.cancel(with: .goingAway, reason: nil)

                let shouldRetry =
                    index < clientIds.count - 1 &&
                    self.isInvalidClientIdError(error)
                if shouldRetry {
                    continue
                }
                break
            }
        }

        let waiters = connectWaiters
        connectWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: lastError ?? GatewayError.connectFailed("Connect failed"))
        }
        throw lastError ?? GatewayError.connectFailed("Connect failed")
    }

    func disconnect() async {
        connected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        await trace("disconnect")

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
        await trace("request: \(method) id=\(reqId)")

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
            await trace("response: \(method) id=\(reqId) ok=false code=\(code ?? "n/a") msg=\(message)")
            throw GatewayError.requestFailed(code: code, message: message)
        }

        if let payload = res.payload {
            await trace("response: \(method) id=\(reqId) ok=true payload=present")
            return try encoder.encode(payload)
        }
        await trace("response: \(method) id=\(reqId) ok=true payload=empty")
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

    func requestDecodedOptional<T: Decodable>(
        method: String,
        params: [String: Any]? = nil,
        timeoutMs: Double? = nil
    ) async throws -> T? {
        let data = try await request(method: method, params: params, timeoutMs: timeoutMs)
        if data.isEmpty { return nil }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Private: Connect handshake

    private func sendConnect(clientId: String) async throws {
        let reqId = UUID().uuidString
        await trace("connect.send: id=\(reqId) clientId=\(clientId)")
        let platform = InstanceIdentity.platformString
        let locale = Locale.preferredLanguages.first ?? Locale.current.identifier

        let clientDisplayName = InstanceIdentity.displayName
        let clientMode = "ui"
        let role = "operator"
        let scopes = ["operator.admin", "operator.approvals", "operator.pairing"]
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        var client: [String: Any] = [
            "id": clientId,
            "displayName": clientDisplayName,
            "version": version,
            "platform": platform,
            "mode": clientMode,
            "instanceId": InstanceIdentity.instanceId,
            "deviceFamily": InstanceIdentity.deviceFamily
        ]
        if let modelIdentifier = InstanceIdentity.modelIdentifier {
            client["modelIdentifier"] = modelIdentifier
        }

        var params: [String: Any] = [
            "minProtocol": GATEWAY_PROTOCOL_VERSION,
            "maxProtocol": GATEWAY_PROTOCOL_VERSION,
            "client": client,
            "caps": [] as [String],
            "locale": locale,
            "userAgent": ProcessInfo.processInfo.operatingSystemVersionString,
            "role": role,
            "scopes": scopes
        ]

        let identity = DeviceIdentityStore.loadOrCreate()
        let storedToken = DeviceAuthStore.loadToken(deviceId: identity.deviceId, role: role)?.token
        let authToken = storedToken ?? self.token
        if let authToken {
            params["auth"] = ["token": authToken]
        } else if let password = self.password {
            params["auth"] = ["password": password]
        }

        let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let connectNonce = try await waitForConnectChallenge()
        let scopesValue = scopes.joined(separator: ",")
        var payloadParts = [
            connectNonce == nil ? "v1" : "v2",
            identity.deviceId,
            clientId,
            clientMode,
            role,
            scopesValue,
            String(signedAtMs),
            authToken ?? ""
        ]
        if let connectNonce {
            payloadParts.append(connectNonce)
        }
        let payload = payloadParts.joined(separator: "|")
        if let signature = DeviceIdentityStore.signPayload(payload, identity: identity),
           let publicKey = DeviceIdentityStore.publicKeyBase64Url(identity) {
            var device: [String: Any] = [
                "id": identity.deviceId,
                "publicKey": publicKey,
                "signature": signature,
                "signedAt": signedAtMs
            ]
            if let connectNonce {
                device["nonce"] = connectNonce
            }
            params["device"] = device
        }

        let frame = RequestFrame(id: reqId, method: "connect", params: AnyCodable(params))
        let data = try encoder.encode(frame)
        try await task?.send(.data(data))

        let response = try await waitForConnectResponse(reqId: reqId)
        try await handleConnectResponse(response, identity: identity, role: role)
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

    private func handleConnectResponse(_ res: ResponseFrame, identity: DeviceIdentity, role: String) async throws {
        if res.ok == false {
            let msg = res.error?["message"]?.value as? String ?? "Connect failed"
            await trace("connect.res: ok=false msg=\(msg)")
            throw GatewayError.connectFailed(msg)
        }

        guard let payload = res.payload else {
            throw GatewayError.connectFailed("Missing payload")
        }

        let payloadData = try encoder.encode(payload)
        let hello = try decoder.decode(HelloOk.self, from: payloadData)
        await trace("connect.res: ok=true protocol=\(hello.protocol)")

        if let tick = hello.policy["tickIntervalMs"]?.value as? Double {
            tickIntervalMs = tick
        } else if let tick = hello.policy["tickIntervalMs"]?.value as? Int {
            tickIntervalMs = Double(tick)
        }

        lastSnapshot = hello

        if let auth = hello.auth,
           let deviceToken = auth["deviceToken"]?.value as? String {
            let authRole = auth["role"]?.value as? String ?? role
            let scopes = (auth["scopes"]?.value as? [Any])?
                .compactMap { $0 as? String } ?? []
            _ = DeviceAuthStore.storeToken(
                deviceId: identity.deviceId,
                role: authRole,
                token: deviceToken,
                scopes: scopes)
        }

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
        let frame: GatewayFrame
        do {
            frame = try decoder.decode(GatewayFrame.self, from: data)
        } catch {
            await trace("recv: decode failed error=\(error.localizedDescription) bytes=\(data.count)")
            return
        }

        switch frame {
        case let .res(res):
            await trace("recv: res id=\(res.id) ok=\(res.ok.map(String.init) ?? "nil")")
            if let waiter = pending.removeValue(forKey: res.id) {
                waiter.resume(returning: .res(res))
            }
        case let .event(evt):
            if evt.event == "connect.challenge" { return }
            await trace("recv: event \(evt.event) seq=\(evt.seq.map(String.init) ?? "nil")")
            await traceEventDetails(evt)
            await pushHandler?(.event(evt))
        default:
            await trace("recv: req")
            break
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        connected = false
        await trace("recv: failed error=\(error.localizedDescription)")

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

    private func waitForConnectChallenge() async throws -> String? {
        guard let task else { return nil }
        do {
            return try await withTimeout(seconds: connectChallengeTimeoutSeconds) {
                while true {
                    let msg = try await task.receive()
                    guard let data = self.decodeMessageData(msg) else { continue }
                    let frame: GatewayFrame
                    do {
                        frame = try self.decoder.decode(GatewayFrame.self, from: data)
                    } catch {
                        await self.trace("challenge: decode failed error=\(error.localizedDescription)")
                        continue
                    }
                    if case let .event(evt) = frame, evt.event == "connect.challenge" {
                        if let payload = evt.payload?.value as? [String: Any],
                           let nonce = payload["nonce"] as? String {
                            await self.trace("challenge: nonce=\(nonce.prefix(6))…")
                            return nonce
                        }
                    }
                }
            }
        } catch {
            if case GatewayError.timeout = error { return nil }
            throw error
        }
    }

    private func isInvalidClientIdError(_ error: Error) -> Bool {
        guard case let GatewayError.connectFailed(msg) = error else { return false }
        let lower = msg.lowercased()
        return lower.contains("invalid connect params") && lower.contains("/client/id")
    }

    private func preferredClientIds() -> [String] {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["ANTHROPOD_GATEWAY_CLIENT_IDS"] {
            let ids = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !ids.isEmpty { return ids }
        }
        if let raw = env["ANTHROPOD_GATEWAY_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return [raw, raw == "clawdbot-macos" ? "moltbot-macos" : "clawdbot-macos"]
        }

        let configName = ClawdbotPaths.configURL.lastPathComponent.lowercased()
        let launchdEnv = GatewayLaunchAgent.snapshot()?.environment ?? [:]
        let marker = launchdEnv["CLAWDBOT_SERVICE_MARKER"]?.lowercased()
        let label = launchdEnv["CLAWDBOT_LAUNCHD_LABEL"]?.lowercased()

        if configName == "clawdbot.json" || marker == "clawdbot" || (label?.contains("clawdbot") == true) {
            return ["clawdbot-macos", "moltbot-macos"]
        }
        return ["moltbot-macos", "clawdbot-macos"]
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

    private func trace(_ message: String) async {
        guard traceEnabled else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) \(message)"
        traceLines.append(line)
        if traceLines.count > traceLimit {
            traceLines.removeFirst(traceLines.count - traceLimit)
        }
        print("[gateway] \(line)")
    }

    private func traceEventDetails(_ event: EventFrame) async {
        guard traceEnabled else { return }
        guard ["agent", "chat", "agent.run", "health", "tick"].contains(event.event) else { return }
        var summary = "event.\(event.event)"
        if let payload = event.payload?.value {
            let rendered = renderJSON(payload, maxChars: 800)
            if !rendered.isEmpty {
                summary += " payload=\(rendered)"
            }
        }
        await trace(summary)
    }

    private func renderJSON(_ value: Any, maxChars: Int) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
           let text = String(data: data, encoding: .utf8)
        {
            if text.count <= maxChars { return text }
            let prefix = text.prefix(maxChars)
            return "\(prefix)…"
        }
        let fallback = String(describing: value)
        if fallback.count <= maxChars { return fallback }
        let prefix = fallback.prefix(maxChars)
        return "\(prefix)…"
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
