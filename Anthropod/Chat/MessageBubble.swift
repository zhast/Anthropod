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

    /// Whether to show timestamp on hover
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.xs) {
            if message.isFromUser {
                Spacer(minLength: LiquidGlass.Spacing.bubbleMinMargin)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: LiquidGlass.Spacing.xxs) {
                // Message content
                Text(message.content)
                    .font(LiquidGlass.Typography.messageBody)
                    .textSelection(.enabled)
                    .padding(.horizontal, LiquidGlass.Spacing.md)
                    .padding(.vertical, LiquidGlass.Spacing.sm)
                    .background(bubbleBackground)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: LiquidGlass.CornerRadius.bubble,
                            style: .continuous
                        )
                    )

                // Timestamp (shown on hover)
                if isHovered {
                    Text(message.timestamp, style: .time)
                        .font(LiquidGlass.Typography.timestamp)
                        .foregroundStyle(LiquidGlass.Colors.secondaryText)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            if !message.isFromUser {
                Spacer(minLength: LiquidGlass.Spacing.bubbleMinMargin)
            }
        }
        .onHover { hovering in
            withAnimation(LiquidGlass.Animation.quick) {
                isHovered = hovering
            }
        }
    }

    private var bubbleBackground: Color {
        message.isFromUser
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

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.xs) {
            VStack(alignment: .leading, spacing: LiquidGlass.Spacing.xxs) {
                if message.content.isEmpty && message.isStreaming {
                    // Show typing indicator when streaming with no content yet
                    StreamingIndicator()
                        .padding(.horizontal, LiquidGlass.Spacing.md)
                        .padding(.vertical, LiquidGlass.Spacing.sm)
                        .background(LiquidGlass.Colors.assistantBubble)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: LiquidGlass.CornerRadius.bubble,
                                style: .continuous
                            )
                        )
                } else {
                    MessageBubble(message: message)
                }
            }

            Spacer(minLength: LiquidGlass.Spacing.bubbleMinMargin)
        }
    }
}

// MARK: - Previews

#Preview("User Message") {
    MessageBubble(message: .previewUser)
        .padding()
}

#Preview("Assistant Message") {
    MessageBubble(message: .previewAssistant)
        .padding()
}

#Preview("Streaming") {
    AssistantMessageBubble(message: Message.assistant("", isStreaming: true))
        .padding()
}
