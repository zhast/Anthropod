//
//  ChatViewModel.swift
//  Anthropod
//
//  State management for chat functionality
//

import SwiftUI
import SwiftData
import CryptoKit

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

    /// Gateway session key currently loaded
    private var gatewaySessionKey: String?

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
            return
        }

        if isConnected {
            await resumeGatewaySession()
        }
    }

    func debugReport() async -> String {
        await gateway.debugReport()
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
        gatewaySessionKey = nil
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
        gateway.onChatEvent { [weak self] event in
            Task { @MainActor in
                self?.handleChatEvent(event)
            }
        }
        gateway.onAgentEvent { [weak self] event in
            Task { @MainActor in
                self?.handleAgentEvent(event)
            }
        }
    }

    private func resumeGatewaySession(sessionKey overrideKey: String? = nil) async {
        guard let modelContext else { return }
        let baseKey = overrideKey ?? gateway.mainSessionKey
        let sessionKey = baseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionKey.isEmpty else { return }

        if gatewaySessionKey != sessionKey {
            gatewaySessionKey = sessionKey
        }
        let sessionId = stableSessionId(for: sessionKey)
        currentSessionId = sessionId

        do {
            let history = try await gateway.chatHistory(sessionKey: sessionKey, limit: 200)
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { message in
                    message.sessionId == sessionId
                }
            )
            if let existing = try? modelContext.fetch(descriptor) {
                for message in existing {
                    modelContext.delete(message)
                }
            }

            for entry in history {
                let trimmed = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                let message = Message(
                    content: trimmed,
                    isFromUser: entry.isUser,
                    timestamp: entry.timestamp,
                    sessionId: sessionId
                )
                modelContext.insert(message)
            }
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stableSessionId(for key: String) -> UUID {
        let hash = SHA256.hash(data: Data(key.utf8))
        let bytes = Array(hash)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
            let snapshotRunId = runId
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    guard let self else { return }
                    guard self.currentRunId == snapshotRunId else { return }
                    if self.currentAssistantMessage?.content.isEmpty == true {
                        Task { await self.resumeGatewaySession() }
                    }
                }
            }
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

    private func handleChatEvent(_ event: ChatRunEvent) {
        if !event.sessionKey.isEmpty, event.sessionKey != gatewaySessionKey {
            gatewaySessionKey = event.sessionKey
            currentSessionId = stableSessionId(for: event.sessionKey)
        }

        if event.isComplete {
            if let error = event.errorMessage, !error.isEmpty {
                errorMessage = error
            }
            currentAssistantMessage?.isStreaming = false
            isLoading = false
            currentRunId = nil
            Task { await resumeGatewaySession(sessionKey: event.sessionKey) }
        }
    }

    private func handleAgentEvent(_ event: AgentStreamEvent) {
        guard !event.runId.isEmpty else { return }
        if let currentRunId, event.runId == currentRunId {
            // ok
        } else if let sessionKey = event.sessionKey,
                  let gatewaySessionKey,
                  sessionKey == gatewaySessionKey
        {
            // Accept events scoped to the current session when runId doesn't match.
        } else {
            return
        }

        let stream = event.stream.lowercased()
        let isAssistant = stream == "assistant" || stream.hasPrefix("assistant.")
        if isAssistant, let text = event.text ?? event.rawText {
            currentAssistantMessage?.content = text
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
