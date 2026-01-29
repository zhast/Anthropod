//
//  MessageBubble.swift
//  Anthropod
//
//  Minimal, clean message bubble view
//

import SwiftUI
import Combine

struct MessageBubble: View {
    let message: Message
    let isGrouped: Bool
    let isLastInGroup: Bool
    let layout: ChatLayout

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.xs) {
            if message.isFromUser {
                Spacer(minLength: layout.bubbleMinMargin)
            }
            Text(message.content)
                .font(LiquidGlass.Typography.messageBody)
                .textSelection(.enabled)
                .padding(.horizontal, layout.bubblePaddingH)
                .padding(.vertical, layout.bubblePaddingV)
                .background(bubbleBackground)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isGrouped ? LiquidGlass.CornerRadius.md : LiquidGlass.CornerRadius.bubble,
                        style: .continuous
                    )
                )
                .overlay(alignment: message.isFromUser ? .bottomTrailing : .bottomLeading) {
                    if isLastInGroup {
                        BubbleTail(fill: bubbleBackground)
                            .offset(x: message.isFromUser ? 2 : -2, y: 2)
                    }
                }

            if !message.isFromUser {
                Spacer(minLength: layout.bubbleMinMargin)
            }
        }
    }

    private var bubbleBackground: Color {
        if message.isSystemError {
            return LiquidGlass.Colors.errorBubble
        }
        return message.isFromUser
            ? LiquidGlass.Colors.userBubble
            : LiquidGlass.Colors.assistantBubble
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicator: View {
    @State private var dotIndex = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(index == dotIndex ? 1.2 : 0.8)
                    .opacity(index == dotIndex ? 1.0 : 0.5)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(LiquidGlass.Animation.quick) {
                dotIndex = (dotIndex + 1) % 3
            }
        }
    }
}

// MARK: - Assistant Bubble with Streaming

struct AssistantMessageBubble: View {
    let message: Message
    let layout: ChatLayout

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.xs) {
            VStack(alignment: .leading, spacing: LiquidGlass.Spacing.xxs) {
                if message.content.isEmpty && message.isStreaming {
                    // Show typing indicator when streaming with no content yet
                    StreamingIndicator()
                        .padding(.horizontal, layout.bubblePaddingH)
                        .padding(.vertical, layout.bubblePaddingV)
                        .background(LiquidGlass.Colors.assistantBubble)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: LiquidGlass.CornerRadius.bubble,
                                style: .continuous
                            )
                        )
                } else {
                    MessageBubble(message: message, isGrouped: false, isLastInGroup: true, layout: layout)
                }
            }

            Spacer(minLength: layout.bubbleMinMargin)
        }
    }
}

// MARK: - Streaming Bubbles (Non-persisted)

struct StreamingAssistantBubble: View {
    let text: String
    let layout: ChatLayout

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.xs) {
            Text(text)
                .font(LiquidGlass.Typography.messageBody)
                .textSelection(.enabled)
                .padding(.horizontal, layout.bubblePaddingH)
                .padding(.vertical, layout.bubblePaddingV)
                .background(LiquidGlass.Colors.assistantBubble)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: LiquidGlass.CornerRadius.bubble,
                        style: .continuous
                    )
                )

            Spacer(minLength: layout.bubbleMinMargin)
        }
    }
}

struct StreamingTypingBubble: View {
    let layout: ChatLayout

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.xs) {
            StreamingIndicator()
                .padding(.horizontal, layout.bubblePaddingH)
                .padding(.vertical, layout.bubblePaddingV)
                .background(LiquidGlass.Colors.assistantBubble)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: LiquidGlass.CornerRadius.bubble,
                        style: .continuous
                    )
                )

            Spacer(minLength: layout.bubbleMinMargin)
        }
    }
}

// MARK: - Bubble Tail

struct BubbleTail: View {
    let fill: Color

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Previews

#Preview("User Message") {
    MessageBubble(message: .previewUser, isGrouped: false, isLastInGroup: true, layout: ChatLayout(isCompact: false))
        .padding()
}

#Preview("Assistant Message") {
    MessageBubble(message: .previewAssistant, isGrouped: false, isLastInGroup: true, layout: ChatLayout(isCompact: false))
        .padding()
}

#Preview("Streaming") {
    AssistantMessageBubble(message: Message.assistant("", isStreaming: true), layout: ChatLayout(isCompact: false))
        .padding()
}
