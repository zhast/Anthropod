//
//  ChatViewModel.swift
//  Anthropod
//
//  State management for chat functionality
//

import SwiftUI
import SwiftData

@MainActor
@Observable
final class ChatViewModel {
    // MARK: - State

    var inputText: String = ""
    var isLoading: Bool = false
    var isListening: Bool = false
    var errorMessage: String?

    /// Current session for message grouping
    var currentSessionId: UUID = UUID()

    // MARK: - Dependencies

    private var modelContext: ModelContext?

    // MARK: - Initialization

    init() {}

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Actions

    func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let modelContext else { return }

        // Create user message
        let userMessage = Message.user(content, sessionId: currentSessionId)
        modelContext.insert(userMessage)

        // Clear input
        inputText = ""

        // Create placeholder for assistant response
        let assistantMessage = Message.assistant("", sessionId: currentSessionId, isStreaming: true)
        modelContext.insert(assistantMessage)

        // Set loading state
        isLoading = true
        errorMessage = nil

        // TODO: Connect to gateway WebSocket for actual AI response
        // For now, simulate a response after a delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            await simulateResponse(for: assistantMessage, userContent: content)
        }
    }

    func toggleVoice() {
        isListening.toggle()
        // TODO: Implement voice input
    }

    func clearError() {
        errorMessage = nil
    }

    func startNewSession() {
        currentSessionId = UUID()
    }

    // MARK: - Private

    private func simulateResponse(for message: Message, userContent: String) async {
        // Simulate streaming response
        let responses = [
            "I understand you said: \"\(userContent)\"",
            "\n\nThis is a demo response from the Anthropod app.",
            " The actual AI integration will connect to the gateway WebSocket."
        ]

        for (index, chunk) in responses.enumerated() {
            try? await Task.sleep(for: .milliseconds(300))
            message.content += chunk

            if index == responses.count - 1 {
                message.isStreaming = false
                isLoading = false
            }
        }
    }
}

// MARK: - Message Queries

extension ChatViewModel {
    /// Fetch descriptor for messages in current session
    var messagesDescriptor: FetchDescriptor<Message> {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { message in
                message.sessionId == currentSessionId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return descriptor
    }

    /// Fetch descriptor for all messages (for sidebar/history)
    static var allMessagesDescriptor: FetchDescriptor<Message> {
        FetchDescriptor<Message>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }
}
