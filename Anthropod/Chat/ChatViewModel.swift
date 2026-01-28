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

    /// Streaming assistant text (not persisted)
    var streamingAssistantText: String?

    /// Local ordering for new messages before history refresh
    private var nextSortIndex: Int = 0

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
        let userMessage = Message.user(content, sessionId: currentSessionId, sortIndex: nextSortIndex)
        nextSortIndex += 1
        modelContext.insert(userMessage)

        // Clear input
        inputText = ""

        streamingAssistantText = nil

        // Set loading state
        isLoading = true
        errorMessage = nil

        // Send to gateway
        Task {
            await sendToGateway(message: content)
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
        streamingAssistantText = nil
        gatewaySessionKey = nil
        nextSortIndex = 0
    }

    func abortCurrentRun() async {
        guard let runId = currentRunId else { return }

        do {
            _ = try await gateway.chatAbort(runId: runId)
            streamingAssistantText = nil
            isLoading = false
            currentRunId = nil
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

            var seenKeys = Set<String>()
            var index = 0
            for entry in history {
                let trimmed = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if let key = dedupeKey(for: entry, content: trimmed) {
                    if seenKeys.contains(key) { continue }
                    seenKeys.insert(key)
                }
                let message = Message(
                    content: trimmed,
                    isFromUser: entry.isUser,
                    timestamp: entry.timestamp,
                    sortIndex: index,
                    sessionId: sessionId
                )
                modelContext.insert(message)
                index += 1
            }
            nextSortIndex = index
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

    private func sendToGateway(message: String) async {
        // Connect if needed
        if !gateway.isConnected {
            await connectToGateway()
        }

        guard gateway.isConnected else {
            errorMessage = "Unable to connect to gateway. Please check that Moltbot is running."
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
                    if self.streamingAssistantText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        Task { await self.resumeGatewaySession() }
                    }
                }
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func handleAgentRunEvent(_ event: AgentRunEvent) {
        if let content = event.content, !content.isEmpty {
            streamingAssistantText = content
        }
        if event.isComplete {
            isLoading = false
            currentRunId = nil
            if let error = event.error, !error.isEmpty {
                errorMessage = error
            }
        }
    }

    private func handleChatEvent(_ event: ChatRunEvent) {
        _ = adoptRunIdIfNeeded(event.runId, sessionKey: event.sessionKey)
        if !event.sessionKey.isEmpty, event.sessionKey != gatewaySessionKey {
            gatewaySessionKey = event.sessionKey
            currentSessionId = stableSessionId(for: event.sessionKey)
        }

        if event.isComplete {
            if let error = event.errorMessage, !error.isEmpty {
                errorMessage = error
            }
            streamingAssistantText = nil
            isLoading = false
            currentRunId = nil
            Task { await resumeGatewaySession(sessionKey: event.sessionKey) }
        }
    }

    private func handleAgentEvent(_ event: AgentStreamEvent) {
        guard adoptRunIdIfNeeded(event.runId, sessionKey: event.sessionKey) else { return }

        let stream = event.stream.lowercased()
        let isAssistant = stream == "assistant" || stream.hasPrefix("assistant.")
        if isAssistant, let text = event.text ?? event.rawText {
            streamingAssistantText = text
        }
    }

    private func adoptRunIdIfNeeded(_ runId: String, sessionKey: String?) -> Bool {
        guard !runId.isEmpty else { return false }

        if let existingRunId = currentRunId {
            if runId == existingRunId { return true }
            if isLoading {
                currentRunId = runId
                return true
            }
            if let sessionKey,
               let gatewaySessionKey,
               sessionKey == gatewaySessionKey
            {
                currentRunId = runId
                return true
            }
            return false
        }

        if isLoading {
            currentRunId = runId
            return true
        }

        if let sessionKey,
           let gatewaySessionKey,
           sessionKey == gatewaySessionKey
        {
            currentRunId = runId
            return true
        }

        return false
    }

    private func dedupeKey(for entry: GatewayChatHistoryMessage, content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let millis = Int(entry.timestamp.timeIntervalSince1970 * 1000)
        return "\(entry.role)|\(millis)|\(trimmed)"
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
            sortBy: [
                SortDescriptor(\.sortIndex, order: .forward),
                SortDescriptor(\.timestamp, order: .forward)
            ]
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
