//
//  ChatView.swift
//  Anthropod
//
//  Main chat view with clean, uncluttered Liquid Glass design
//

import SwiftUI
import AppKit
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.timestamp) private var messages: [Message]

    @State private var viewModel = ChatViewModel()
    @State private var scrolledToBottom = true
    @State private var expandedGroupIds: Set<UUID> = []
    @AppStorage(AnthropodDefaults.compactLayout) private var compactLayout = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content layer (NOT glass - messages are primary content)
            messageList

            // Navigation layer (glass - floats above content)
            inputBar

            // Connection status overlay
            if viewModel.isConnecting {
                connectionOverlay
            }

        }
        .frame(
            minWidth: LiquidGlass.Window.minWidth,
            minHeight: LiquidGlass.Window.minHeight
        )
        .toolbar {
            ToolbarItem(placement: .automatic) {
                statusMenu
            }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
            Task {
                await viewModel.connectToGateway()
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            let scrollToBottom: (Bool) -> Void = { animated in
                if animated {
                    withAnimation(LiquidGlass.Animation.spring) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            ScrollView {
                LazyVStack(spacing: layout.groupGap) {
                    // Empty state
                    if sessionMessages.isEmpty {
                        emptyState
                    }

                    // Messages
                    ForEach(messageRows) { row in
                        switch row.kind {
                        case let .divider(date):
                            DateDivider(date: date, layout: layout)
                        case let .group(group):
                            MessageGroupView(
                                group: group,
                                isExpanded: expandedGroupIds.contains(group.id),
                                layout: layout,
                                onToggle: { toggleGroup(group.id) }
                            )
                        }
                    }

                    if hasStreamingText, let text = viewModel.streamingAssistantText {
                        StreamingAssistantBubble(text: text, layout: layout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if viewModel.isLoading {
                        StreamingTypingBubble(layout: layout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, layout.listHorizontalPadding)
                .padding(.top, layout.listTopPadding)
                .padding(.bottom, LiquidGlass.Spacing.scrollBottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: sessionMessages.count) { _, _ in
                scrollToBottom(true)
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    scrollToBottom(true)
                }
            }
            .onChange(of: viewModel.streamingAssistantText) { _, _ in
                scrollToBottom(false)
            }
            .onChange(of: viewModel.currentSessionId) { _, _ in
                scrollToBottom(false)
            }
        }
    }

    private var sessionMessages: [Message] {
        let filtered = messages.filter { $0.sessionId == viewModel.currentSessionId }
        return filtered.sorted {
            if let lhs = $0.sortIndex, let rhs = $1.sortIndex, lhs != rhs {
                return lhs < rhs
            }
            if $0.sortIndex != nil, $1.sortIndex == nil { return true }
            if $0.sortIndex == nil, $1.sortIndex != nil { return false }
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var messageRows: [MessageRow] {
        guard !sessionMessages.isEmpty else { return [] }
        var rows: [MessageRow] = []
        let calendar = Calendar.current
        var currentDay: Date?
        var currentGroup: MessageGroup?

        for message in sessionMessages {
            let day = calendar.startOfDay(for: message.timestamp)
            if let dayValue = currentDay, !calendar.isDate(day, inSameDayAs: dayValue) {
                if let group = currentGroup {
                    rows.append(MessageRow(kind: .group(group)))
                    currentGroup = nil
                }
                rows.append(MessageRow(kind: .divider(day)))
                currentDay = day
            } else if currentDay == nil {
                rows.append(MessageRow(kind: .divider(day)))
                currentDay = day
            }

            if var group = currentGroup,
               group.isFromUser == message.isFromUser,
               group.isSystemError == message.isSystemError
            {
                group.messages.append(message)
                group.lastTimestamp = message.timestamp
                currentGroup = group
            } else {
                if let group = currentGroup {
                    rows.append(MessageRow(kind: .group(group)))
                }
                currentGroup = MessageGroup(
                    id: message.id,
                    isFromUser: message.isFromUser,
                    isSystemError: message.isSystemError,
                    messages: [message],
                    day: day,
                    lastTimestamp: message.timestamp
                )
            }
        }

        if let group = currentGroup {
            rows.append(MessageRow(kind: .group(group)))
        }

        return rows
    }

    private func toggleGroup(_ id: UUID) {
        if expandedGroupIds.contains(id) {
            expandedGroupIds.remove(id)
        } else {
            expandedGroupIds.insert(id)
        }
    }

    private struct MessageRow: Identifiable {
        enum Kind {
            case divider(Date)
            case group(MessageGroup)
        }

        let kind: Kind

        var id: String {
            switch kind {
            case let .divider(date):
                return "day-\(date.timeIntervalSinceReferenceDate)"
            case let .group(group):
                return "group-\(group.id.uuidString)"
            }
        }
    }

    private struct MessageGroup: Equatable {
        let id: UUID
        let isFromUser: Bool
        let isSystemError: Bool
        var messages: [Message]
        let day: Date
        var lastTimestamp: Date
    }

    private struct MessageGroupView: View {
        let group: MessageGroup
        let isExpanded: Bool
        let layout: ChatLayout
        let onToggle: () -> Void

        var body: some View {
            VStack(
                alignment: group.isFromUser ? .trailing : .leading,
                spacing: layout.stackSpacing
            ) {
                ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, message in
                    let isGrouped = group.messages.count > 1
                    let isLast = index == group.messages.count - 1
                    MessageBubble(message: message, isGrouped: isGrouped, isLastInGroup: isLast, layout: layout)
                        .frame(
                            maxWidth: .infinity,
                            alignment: group.isFromUser ? .trailing : .leading
                        )
                }
            }
            .overlay(alignment: group.isFromUser ? .topTrailing : .topLeading) {
                if isExpanded {
                    Text(group.lastTimestamp, style: .time)
                        .font(LiquidGlass.Typography.timestamp)
                        .foregroundStyle(LiquidGlass.Colors.secondaryText)
                        .offset(y: layout.timestampOffsetY)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(LiquidGlass.Animation.quick) {
                    onToggle()
                }
            }
        }
    }

    private struct DateDivider: View {
        let date: Date
        let layout: ChatLayout

        var body: some View {
            HStack(spacing: LiquidGlass.Spacing.sm) {
                line
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(LiquidGlass.Colors.secondaryText)
                    .padding(.horizontal, LiquidGlass.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: LiquidGlass.CornerRadius.pill)
                            .fill(Color.secondary.opacity(0.08))
                    )
                line
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, layout.dividerVerticalPadding)
        }

        private var line: some View {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
        }
    }

    private var hasStreamingText: Bool {
        guard let text = viewModel.streamingAssistantText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        GlassEffectContainer {
            ChatInputBar(text: $viewModel.inputText) {
                viewModel.sendMessage()
            }
        }
        .padding(.horizontal, LiquidGlass.Spacing.inputBarHorizontal)
        .padding(.bottom, LiquidGlass.Spacing.inputBarBottom)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LiquidGlass.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Start a conversation")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !viewModel.isConnected && !viewModel.isConnecting {
                Button("Connect to Gateway") {
                    Task {
                        await viewModel.connectToGateway()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, LiquidGlass.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Connection Status

    private var connectionIndicator: some View {
        let status = connectionStatus
        return Circle()
            .fill(status.color)
            .frame(width: 7, height: 7)
            .accessibilityLabel(status.title)
            .animation(LiquidGlass.Animation.quick, value: status.title)
    }

    private var connectionStatus: (title: String, color: Color) {
        if viewModel.isConnecting {
            return ("Connecting", .orange)
        }
        if let error = viewModel.errorMessage, !error.isEmpty {
            return ("Error", .red)
        }
        return viewModel.isConnected ? ("Connected", .green) : ("Offline", .secondary)
    }

    private var connectionOverlay: some View {
        VStack(spacing: LiquidGlass.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Connecting to gateway...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var statusMenu: some View {
        Menu {
            Section("Connection") {
                Text("Status: \(connectionStatus.title)")
                if let mode = viewModel.connectionModeLabel {
                    Text("Mode: \(mode)")
                }
                if let restartMode = viewModel.restartModeLabel {
                    Text("Restart: \(restartMode)")
                }
                if let runStatus = viewModel.runStatusLabel {
                    Text("Run: \(runStatus)")
                }
            }

            Section("Model") {
                Text(viewModel.effectiveModelLabel)
                if let remaining = viewModel.contextRemainingTokens {
                    if let percent = viewModel.contextRemainingPercent {
                        Text("Context left: \(formatTokens(remaining)) (\(percent)%)")
                    } else {
                        Text("Context left: \(formatTokens(remaining))")
                    }
                } else if let context = viewModel.effectiveContextTokens {
                    Text("Context: \(formatTokens(context)) tokens")
                }
            }

            Section("Session") {
                Text("Key: \(viewModel.activeSessionKey)")
                if let updated = viewModel.statusLastUpdated {
                    Text("Updated: \(updated, style: .time)")
                }
                if let error = viewModel.statusError, !error.isEmpty {
                    Text("Status error: \(error)")
                }
            }

            Divider()
            Button("Refresh status") {
                Task { await viewModel.refreshStatusSnapshot() }
            }
            Button("Compact conversation") {
                Task { await viewModel.compactConversation() }
            }
            Button("Restart agent") {
                Task { await viewModel.restartGateway() }
            }
            Button("Reconnect") {
                Task { await viewModel.connectToGateway() }
            }
        } label: {
            statusMenuLabel
        }
        .menuIndicator(.hidden)
        .help("Connection and model status")
    }

    private var statusMenuLabel: some View {
        Image(systemName: "fossil.shell")
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .overlay(alignment: .topTrailing) {
                connectionIndicator
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                    }
                    .offset(x: 4, y: -4)
            }
            .padding(.horizontal, 6)
            .accessibilityLabel("Status menu")
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            let value = Double(tokens) / 1000
            return String(format: "%.0fk", value)
        }
        return "\(tokens)"
    }

    private var layout: ChatLayout {
        ChatLayout(isCompact: compactLayout)
    }
}

// MARK: - Chat View with Voice

struct ChatViewWithVoice: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.timestamp) private var messages: [Message]

    @State private var viewModel = ChatViewModel()
    @State private var showDebugOverlay = false
    @State private var debugReport = ""
    @State private var didCopyDebug = false
    @AppStorage(AnthropodDefaults.compactLayout) private var compactLayout = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content layer
            ScrollViewReader { proxy in
                ScrollView {
                LazyVStack(spacing: layout.groupGap) {
                        if messages.isEmpty {
                            emptyState
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message, isGrouped: false, isLastInGroup: true, layout: layout)
                                .id(message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, layout.listHorizontalPadding)
                    .padding(.top, layout.listTopPadding)
                    .padding(.bottom, LiquidGlass.Spacing.scrollBottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation(LiquidGlass.Animation.spring) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // Navigation layer with voice
            GlassEffectContainer {
                ChatInputBarWithVoice(
                    text: $viewModel.inputText,
                    onSend: { viewModel.sendMessage() },
                    onVoice: { viewModel.toggleVoice() },
                    isListening: viewModel.isListening
                )
            }
            .padding(.horizontal, LiquidGlass.Spacing.inputBarHorizontal)
            .padding(.bottom, LiquidGlass.Spacing.inputBarBottom)

            // Connection overlay
            if viewModel.isConnecting {
                connectionOverlay
            }

            if showDebugOverlay {
                debugOverlay
            }
        }
        .frame(
            minWidth: LiquidGlass.Window.minWidth,
            minHeight: LiquidGlass.Window.minHeight
        )
        .onAppear {
            viewModel.configure(with: modelContext)
            Task {
                await viewModel.connectToGateway()
            }
        }
        .toolbar {
            if showDebugButton {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            debugReport = await viewModel.debugReport()
                            showDebugOverlay = true
                        }
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                    .help("Show connection debug info")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiquidGlass.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Start a conversation")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !viewModel.isConnected && !viewModel.isConnecting {
                Button("Connect to Gateway") {
                    Task {
                        await viewModel.connectToGateway()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, LiquidGlass.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var connectionOverlay: some View {
        VStack(spacing: LiquidGlass.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Connecting to gateway...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var layout: ChatLayout {
        ChatLayout(isCompact: compactLayout)
    }

    private var debugOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: LiquidGlass.Spacing.md) {
                HStack {
                    Text("Gateway Debug Info")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        Task {
                            debugReport = await viewModel.debugReport()
                        }
                    }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(debugReport, forType: .string)
                        didCopyDebug = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            didCopyDebug = false
                        }
                    }
                    Button("Close") {
                        showDebugOverlay = false
                    }
                }

                if didCopyDebug {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    Text(debugReport.isEmpty ? "No debug info yet." : debugReport)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, LiquidGlass.Spacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: 320)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(LiquidGlass.Spacing.lg)
            .frame(maxWidth: 640)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05))
            )
        }
    }

    private var showDebugButton: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

}

// MARK: - Previews

#Preview("Chat View") {
    ChatView()
        .modelContainer(for: Message.self, inMemory: true)
}

#Preview("Chat View with Voice") {
    ChatViewWithVoice()
        .modelContainer(for: Message.self, inMemory: true)
}

#Preview("With Messages") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Message.self, configurations: config)

    // Add sample messages
    for message in Message.previewConversation {
        container.mainContext.insert(message)
    }

    return ChatView()
        .modelContainer(container)
}
