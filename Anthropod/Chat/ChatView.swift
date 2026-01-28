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
    @State private var showDebugOverlay = false
    @State private var debugReport = ""
    @State private var didCopyDebug = false

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

            if showDebugOverlay {
                debugOverlay
            }
        }
        .frame(
            minWidth: LiquidGlass.Window.minWidth,
            minHeight: LiquidGlass.Window.minHeight
        )
        .toolbar {
            ToolbarItem(placement: .automatic) {
                connectionStatusIndicator
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        debugReport = await viewModel.debugReport()
                        showDebugOverlay = true
                    }
                } label: {
                    Image(systemName: "ladybug")
                }
                .help("Show connection debug info")
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
            Button("Debug") {
                Task {
                    debugReport = await viewModel.debugReport()
                    showDebugOverlay = true
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: LiquidGlass.Spacing.messagePadding) {
                    // Empty state
                    if messages.isEmpty {
                        emptyState
                    }

                    // Messages
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, LiquidGlass.Spacing.lg)
                .padding(.top, LiquidGlass.Spacing.lg)
                .padding(.bottom, LiquidGlass.Spacing.scrollBottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(LiquidGlass.Animation.spring) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
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

    private var connectionStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(viewModel.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
}

// MARK: - Chat View with Voice

struct ChatViewWithVoice: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.timestamp) private var messages: [Message]

    @State private var viewModel = ChatViewModel()
    @State private var showDebugOverlay = false
    @State private var debugReport = ""
    @State private var didCopyDebug = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content layer
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: LiquidGlass.Spacing.messagePadding) {
                        if messages.isEmpty {
                            emptyState
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, LiquidGlass.Spacing.lg)
                    .padding(.top, LiquidGlass.Spacing.lg)
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
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        debugReport = await viewModel.debugReport()
                        showDebugOverlay = true
                    }
                } label: {
                    Image(systemName: "ladybug")
                }
                .help("Show connection debug info")
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
