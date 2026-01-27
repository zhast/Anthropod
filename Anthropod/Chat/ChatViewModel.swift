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
    var isConnected: Bool = false
    var isConnecting: Bool = false

    /// Current session for message grouping
    var currentSessionId: UUID = UUID()

    /// Current run ID for streaming response
    private var currentRunId: String?

    /// Current assistant message being streamed
    private var currentAssistantMessage: Message?

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private let gateway = GatewayService.shared

    // MARK: - Initialization

    init() {}

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        setupEventHandlers()
    }

    // MARK: - Connection

    func connectToGateway() async {
        isConnecting = true
        await gateway.connect()
        isConnected = gateway.isConnected
        isConnecting = false

        if let error = gateway.connectionError {
            errorMessage = error
        }
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
        currentAssistantMessage = assistantMessage

        // Set loading state
        isLoading = true
        errorMessage = nil

        // Send to gateway
        Task {
            await sendToGateway(message: content, assistantMessage: assistantMessage)
        }
    }

    func toggleVoice() {
        isListening.toggle()
    }

    func clearError() {
        errorMessage = nil
    }

    func startNewSession() {
        currentSessionId = UUID()
        currentRunId = nil
        currentAssistantMessage = nil
    }

    func abortCurrentRun() async {
        guard let runId = currentRunId else { return }

        do {
            _ = try await gateway.chatAbort(runId: runId)
            currentAssistantMessage?.isStreaming = false
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func setupEventHandlers() {
        gateway.onAgentRun { [weak self] event in
            Task { @MainActor in
                self?.handleAgentRunEvent(event)
            }
        }
    }

    private func sendToGateway(message: String, assistantMessage: Message) async {
        // Connect if needed
        if !gateway.isConnected {
            await connectToGateway()
        }

        guard gateway.isConnected else {
            assistantMessage.content = "Unable to connect to gateway. Please check that Moltbot is running."
            assistantMessage.isStreaming = false
            isLoading = false
            return
        }

        do {
            let runId = try await gateway.chatSend(message: message)
            currentRunId = runId
        } catch {
            assistantMessage.content = "Error: \(error.localizedDescription)"
            assistantMessage.isStreaming = false
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func handleAgentRunEvent(_ event: AgentRunEvent) {
        guard let assistantMessage = currentAssistantMessage else { return }

        // Update content if provided
        if let content = event.content {
            assistantMessage.content = content
        }

        // Check if complete
        if event.isComplete {
            assistantMessage.isStreaming = false
            isLoading = false
            currentRunId = nil

            if let error = event.error {
                errorMessage = error
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
