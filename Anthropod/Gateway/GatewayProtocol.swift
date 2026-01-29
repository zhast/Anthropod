//
//  GatewayProtocol.swift
//  Anthropod
//
//  Gateway WebSocket protocol types
//

import Foundation

// MARK: - Protocol Version

nonisolated let GATEWAY_PROTOCOL_VERSION = 3

// MARK: - AnyCodable

/// A type-erased Codable value for dynamic JSON
@preconcurrency
nonisolated struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated let value: Any

    nonisolated init(_ value: Any) {
        self.value = value
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Request Frame

@preconcurrency
nonisolated struct RequestFrame: Codable, Sendable {
    nonisolated let type: String
    nonisolated let id: String
    nonisolated let method: String
    nonisolated let params: AnyCodable?

    nonisolated init(type: String = "req", id: String = UUID().uuidString, method: String, params: AnyCodable? = nil) {
        self.type = type
        self.id = id
        self.method = method
        self.params = params
    }
}

// MARK: - Response Frame

@preconcurrency
nonisolated struct ResponseFrame: Codable, Sendable {
    nonisolated let type: String
    nonisolated let id: String
    nonisolated let ok: Bool?
    nonisolated let payload: AnyCodable?
    nonisolated let error: [String: AnyCodable]?
}

// MARK: - Event Frame

@preconcurrency
nonisolated struct EventFrame: Codable, Sendable {
    nonisolated let type: String
    nonisolated let event: String
    nonisolated let payload: AnyCodable?
    nonisolated let seq: Int?
    nonisolated let stateVersion: [String: AnyCodable]?
}

// MARK: - Gateway Frame (discriminated union)

@preconcurrency
nonisolated enum GatewayFrame: Sendable, Decodable {
    case req(RequestFrame)
    case res(ResponseFrame)
    case event(EventFrame)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "req":
            self = .req(try RequestFrame(from: decoder))
        case "res":
            self = .res(try ResponseFrame(from: decoder))
        case "event":
            self = .event(try EventFrame(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown frame type: \(type)")
        }
    }
}

// MARK: - Hello Response

@preconcurrency
nonisolated struct HelloOk: Codable, Sendable {
    nonisolated let type: String
    nonisolated let `protocol`: Int
    nonisolated let server: [String: AnyCodable]
    nonisolated let features: [String: AnyCodable]?
    nonisolated let snapshot: HelloSnapshot
    nonisolated let canvasHostUrl: String?
    nonisolated let auth: [String: AnyCodable]?
    nonisolated let policy: [String: AnyCodable]

    private enum CodingKeys: String, CodingKey {
        case type
        case `protocol`
        case server
        case features
        case snapshot
        case canvasHostUrl
        case auth
        case policy
    }
}

@preconcurrency
nonisolated struct HelloSnapshot: Codable, Sendable {
    nonisolated let presence: [AnyCodable]?
    nonisolated let health: AnyCodable?
    nonisolated let stateVersion: [String: Int]?
    nonisolated let uptimeMs: Int?
    nonisolated let configPath: String?
    nonisolated let stateDir: String?
    nonisolated let sessionDefaults: [String: AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case presence
        case health
        case stateVersion
        case uptimeMs
        case configPath
        case stateDir
        case sessionDefaults
    }
}

// MARK: - Chat Types

@preconcurrency
nonisolated struct ChatHistoryPayload: Decodable, Sendable {
    nonisolated let sessionKey: String
    nonisolated let sessionId: String?
    nonisolated let messages: [GatewayChatHistoryMessage]
    nonisolated let thinkingLevel: String?
}

@preconcurrency
nonisolated struct GatewayChatHistoryMessage: Decodable, Sendable {
    nonisolated let role: String
    nonisolated let content: String
    nonisolated let ts: Int?

    nonisolated var isUser: Bool { role == "user" }
    nonisolated var timestamp: Date {
        let millis = ts ?? Int(Date().timeIntervalSince1970 * 1000)
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case text
        case ts
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = (try? container.decode(String.self, forKey: .role)) ?? "assistant"
        self.ts = (try? container.decode(Int.self, forKey: .ts))
            ?? (try? container.decode(Int.self, forKey: .timestamp))

        if let direct = try? container.decode(String.self, forKey: .content) {
            self.content = direct
            return
        }

        if let items = try? container.decode([GatewayChatContentItem].self, forKey: .content) {
            let joined = items.compactMap { $0.text }.joined(separator: "")
            self.content = joined
            return
        }

        if let fallback = try? container.decode(String.self, forKey: .text) {
            self.content = fallback
            return
        }

        self.content = ""
    }
}

nonisolated private struct GatewayChatContentItem: Decodable {
    let type: String?
    let text: String?
}

@preconcurrency
nonisolated struct ChatSendResponse: Decodable, Sendable {
    nonisolated let runId: String?
    nonisolated let status: String?
}

// MARK: - Models

@preconcurrency
nonisolated struct ModelChoice: Decodable, Sendable, Identifiable, Hashable {
    nonisolated let id: String
    nonisolated let name: String
    nonisolated let provider: String
    nonisolated let contextWindow: Int?
    nonisolated let reasoning: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case contextWindow
        case reasoning
    }
}

@preconcurrency
struct ModelsListResult: Decodable, Sendable {
    nonisolated let models: [ModelChoice]
}

// MARK: - Sessions

@preconcurrency
nonisolated struct GatewaySessionsDefaults: Decodable, Sendable {
    nonisolated let modelProvider: String?
    nonisolated let model: String?
    nonisolated let contextTokens: Int?
}

@preconcurrency
nonisolated struct GatewaySessionRow: Decodable, Sendable {
    nonisolated let key: String
    nonisolated let modelProvider: String?
    nonisolated let model: String?
    nonisolated let contextTokens: Int?
    nonisolated let inputTokens: Int?
    nonisolated let outputTokens: Int?
    nonisolated let totalTokens: Int?
}

@preconcurrency
struct SessionsListResult: Decodable, Sendable {
    nonisolated let defaults: GatewaySessionsDefaults
    nonisolated let sessions: [GatewaySessionRow]
}

// MARK: - Gateway Push Events

enum GatewayPush: Sendable {
    case snapshot(HelloOk)
    case event(EventFrame)
    case seqGap(expected: Int, received: Int)
}

// MARK: - Chat Event Types

struct AgentRunEvent: Sendable {
    let sessionKey: String
    let runId: String
    let status: String
    let content: String?
    let error: String?
}

extension AgentRunEvent {
    init?(from event: EventFrame) {
        guard event.event == "agent.run" else { return nil }
        guard let payload = event.payload?.value as? [String: Any] else { return nil }

        self.sessionKey = payload["sessionKey"] as? String ?? ""
        self.runId = payload["runId"] as? String ?? ""
        self.status = payload["status"] as? String ?? ""
        self.content = payload["content"] as? String
        self.error = payload["error"] as? String
    }

    var isComplete: Bool {
        status == "complete" || status == "error" || status == "aborted"
    }

    var isStreaming: Bool {
        status == "streaming" || status == "running"
    }
}

// MARK: - Chat/Agent Stream Events

struct ChatRunEvent: Sendable {
    let sessionKey: String
    let runId: String
    let state: String
    let errorMessage: String?
}

extension ChatRunEvent {
    init?(from event: EventFrame) {
        guard event.event == "chat" else { return nil }
        guard let payload = event.payload?.value as? [String: Any] else { return nil }
        self.sessionKey = payload["sessionKey"] as? String ?? ""
        self.runId = payload["runId"] as? String ?? ""
        if let state = payload["state"] as? String {
            self.state = state
        } else if let state = payload["state"] as? [String: Any],
                  let value = state["value"] as? String {
            self.state = value
        } else {
            self.state = ""
        }
        self.errorMessage = payload["errorMessage"] as? String
    }

    var isComplete: Bool {
        state == "final" || state == "aborted" || state == "error"
    }
}

struct AgentStreamEvent: Sendable {
    let runId: String
    let sessionKey: String?
    let seq: Int?
    let stream: String
    let text: String?
    let rawText: String?
}

extension AgentStreamEvent {
    init?(from event: EventFrame) {
        guard event.event == "agent" else { return nil }
        guard let payload = event.payload?.value as? [String: Any] else { return nil }
        self.runId = payload["runId"] as? String ?? ""
        self.sessionKey = payload["sessionKey"] as? String
        self.seq = payload["seq"] as? Int
        self.stream = payload["stream"] as? String ?? ""
        var extracted: String?
        var raw: String?
        if let data = payload["data"] as? [String: Any] {
            raw = data.description
            if let text = data["text"] as? String {
                extracted = text
            } else if let delta = data["delta"] as? String {
                extracted = delta
            } else if let content = data["content"] as? String {
                extracted = content
            } else if let message = data["message"] as? String {
                extracted = message
            } else if let blocks = data["blocks"] as? [[String: Any]] {
                let parts = blocks.compactMap { block -> String? in
                    if let text = block["text"] as? String { return text }
                    if let content = block["content"] as? String { return content }
                    return nil
                }
                if !parts.isEmpty {
                    extracted = parts.joined(separator: "")
                }
            } else if let content = data["content"] as? [[String: Any]] {
                let parts = content.compactMap { item -> String? in
                    if let text = item["text"] as? String { return text }
                    if let content = item["content"] as? String { return content }
                    return nil
                }
                if !parts.isEmpty {
                    extracted = parts.joined(separator: "")
                }
            }
        }
        self.text = extracted
        self.rawText = raw
    }
}
