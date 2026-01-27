//
//  ChatInputBar.swift
//  Anthropod
//
//  Glass-styled input bar for composing messages
//

import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    /// Maximum height for the text field before scrolling
    private let maxTextFieldHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.sm) {
            // Text input
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(LiquidGlass.Typography.inputPlaceholder)
                .focused($isFocused)
                .lineLimit(1...6)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    }
                }

            // Send button
            SendButton(isEnabled: canSend) {
                sendMessage()
            }
        }
        .padding(.horizontal, LiquidGlass.Spacing.inputBarPaddingH)
        .padding(.vertical, LiquidGlass.Spacing.inputBarPaddingV)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidGlass.CornerRadius.inputBar))
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        guard canSend else { return }
        onSend()
    }
}

// MARK: - Extended Input Bar with Voice

struct ChatInputBarWithVoice: View {
    @Binding var text: String
    let onSend: () -> Void
    let onVoice: () -> Void
    let isListening: Bool

    @FocusState private var isFocused: Bool
    @Namespace private var inputNamespace

    var body: some View {
        GlassEffectContainer(spacing: LiquidGlass.Spacing.xs) {
            HStack(alignment: .bottom, spacing: LiquidGlass.Spacing.sm) {
                // Text input
                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(LiquidGlass.Typography.inputPlaceholder)
                    .focused($isFocused)
                    .lineLimit(1...6)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }

                // Action buttons
                if text.isEmpty {
                    VoiceButton(isListening: isListening, action: onVoice)
                        .glassEffectID("action", in: inputNamespace)
                } else {
                    SendButton(isEnabled: canSend, action: onSend)
                        .glassEffectID("action", in: inputNamespace)
                }
            }
            .padding(.horizontal, LiquidGlass.Spacing.inputBarPaddingH)
            .padding(.vertical, LiquidGlass.Spacing.inputBarPaddingV)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidGlass.CornerRadius.inputBar))
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Previews

#Preview("Input Bar") {
    VStack {
        Spacer()
        ChatInputBar(text: .constant(""), onSend: {})
            .padding()
    }
    .frame(height: 200)
}

#Preview("Input Bar with Text") {
    VStack {
        Spacer()
        ChatInputBar(text: .constant("Hello, this is a test message"), onSend: {})
            .padding()
    }
    .frame(height: 200)
}

#Preview("Input Bar with Voice") {
    VStack {
        Spacer()
        ChatInputBarWithVoice(
            text: .constant(""),
            onSend: {},
            onVoice: {},
            isListening: false
        )
        .padding()
    }
    .frame(height: 200)
}
