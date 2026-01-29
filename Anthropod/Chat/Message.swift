//
//  Message.swift
//  Anthropod
//
//  SwiftData model for chat messages
//

import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var content: String
    var isFromUser: Bool
    var timestamp: Date
    var sortIndex: Int?

    /// Optional session/conversation grouping
    var sessionId: UUID?

    /// For assistant messages: whether the response is still streaming
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        content: String,
        isFromUser: Bool,
        timestamp: Date = Date(),
        sortIndex: Int? = nil,
        sessionId: UUID? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.sortIndex = sortIndex
        self.sessionId = sessionId
        self.isStreaming = isStreaming
    }
}

// MARK: - Convenience

extension Message {
    static func user(_ content: String, sessionId: UUID? = nil, sortIndex: Int? = nil) -> Message {
        Message(content: content, isFromUser: true, sortIndex: sortIndex, sessionId: sessionId)
    }

    static func assistant(_ content: String, sessionId: UUID? = nil, sortIndex: Int? = nil, isStreaming: Bool = false) -> Message {
        Message(content: content, isFromUser: false, sortIndex: sortIndex, sessionId: sessionId, isStreaming: isStreaming)
    }

    static let systemErrorPrefix = "Error: "

    var isSystemError: Bool {
        !isFromUser && content.hasPrefix(Self.systemErrorPrefix)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension Message {
    static let previewUser = Message.user("Hello, how can you help me today?", sortIndex: 0)
    static let previewAssistant = Message.assistant("Hi! I'm here to help. What would you like to know?", sortIndex: 1)

    static let previewConversation: [Message] = [
        Message.user("What's the weather like?", sortIndex: 0),
        Message.assistant("I don't have access to real-time weather data, but I can help you find a weather service or app that would be perfect for your needs.", sortIndex: 1),
        Message.user("Can you recommend one?", sortIndex: 2),
        Message.assistant("Sure! Here are some popular options:\n\n- Weather.com\n- Apple Weather (built into iOS/macOS)\n- Dark Sky API for developers\n\nWould you like more details about any of these?", sortIndex: 3)
    ]
}
#endif
