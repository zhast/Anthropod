//
//  ChatView.swift
//  Anthropod
//
//  Main chat view with clean, uncluttered Liquid Glass design
//

import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.timestamp) private var messages: [Message]

    @State private var viewModel = ChatViewModel()
    @State private var scrolledToBottom = true

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content layer (NOT glass - messages are primary content)
            messageList

            // Navigation layer (glass - floats above content)
            inputBar
        }
        .frame(
            minWidth: LiquidGlass.Window.minWidth,
            minHeight: LiquidGlass.Window.minHeight
        )
        .onAppear {
            viewModel.configure(with: modelContext)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - Chat View with Voice

struct ChatViewWithVoice: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.timestamp) private var messages: [Message]

    @State private var viewModel = ChatViewModel()

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
        }
        .frame(
            minWidth: LiquidGlass.Window.minWidth,
            minHeight: LiquidGlass.Window.minHeight
        )
        .onAppear {
            viewModel.configure(with: modelContext)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
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
