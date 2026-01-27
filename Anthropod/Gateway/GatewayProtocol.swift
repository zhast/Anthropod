//
//  GatewayProtocol.swift
//  Anthropod
//
//  Gateway WebSocket protocol types
//

import Foundation

// MARK: - Protocol Version

let GATEWAY_PROTOCOL_VERSION = 3

// MARK: - AnyCodable

/// A type-erased Codable value for dynamic JSON
@preconcurrency
struct AnyCodable: Codable, @unchecked Sendable {
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
struct RequestFrame: Codable, Sendable {
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
struct ResponseFrame: Codable, Sendable {
    nonisolated let type: String
    nonisolated let id: String
    nonisolated let ok: Bool?
    nonisolated let payload: AnyCodable?
    nonisolated let error: [String: AnyCodable]?
}

// MARK: - Event Frame

@preconcurrency
struct EventFrame: Codable, Sendable {
    nonisolated let type: String
    nonisolated let event: String
    nonisolated let payload: AnyCodable?
    nonisolated let seq: Int?
    nonisolated let stateVersion: StateVersion?

    @preconcurrency
    struct StateVersion: Codable, Sendable {
        nonisolated let presence: Int?
        nonisolated let health: Int?
    }
}

// MARK: - Gateway Frame (discriminated union)

@preconcurrency
enum GatewayFrame: Sendable, Decodable {
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
struct HelloOk: Codable, Sendable {
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
        case canvasHostUrl = "canvashosturl"
        case auth
        case policy
    }
}

@preconcurrency
struct HelloSnapshot: Codable, Sendable {
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
        case stateVersion = "stateversion"
        case uptimeMs = "uptimems"
        case configPath = "configpath"
        case stateDir = "statedir"
        case sessionDefaults = "sessiondefaults"
    }
}

// MARK: - Chat Types

@preconcurrency
struct ChatHistoryPayload: Codable, Sendable {
    nonisolated let sessionKey: String
    nonisolated let messages: [ChatMessage]
}

@preconcurrency
struct ChatMessage: Codable, Sendable, Identifiable {
    nonisolated let id: String
    nonisolated let role: String
    nonisolated let content: String
    nonisolated let ts: Int

    nonisolated var isUser: Bool { role == "user" }
    nonisolated var timestamp: Date { Date(timeIntervalSince1970: TimeInterval(ts) / 1000) }
}

@preconcurrency
struct ChatSendResponse: Codable, Sendable {
    nonisolated let ok: Bool
    nonisolated let runId: String?
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
