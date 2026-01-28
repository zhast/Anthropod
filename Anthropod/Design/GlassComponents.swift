//
//  GlassComponents.swift
//  Anthropod
//
//  Reusable Liquid Glass components and view modifiers (macOS 26 Tahoe)
//

import SwiftUI

// MARK: - Glass Button Style

/// A button style that applies interactive glass effect
struct GlassButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(LiquidGlass.Animation.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }

    static func glass(tint: Color) -> GlassButtonStyle {
        GlassButtonStyle(tint: tint)
    }
}

// MARK: - Glass Card

/// A container view with glass background
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = LiquidGlass.CornerRadius.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Glass Toolbar

/// A floating toolbar with glass effect
struct GlassToolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: LiquidGlass.Spacing.sm) {
            content()
        }
    }
}

// MARK: - Send Button

/// Circular send button with tinted glass effect
struct SendButton: View {
    let action: () -> Void
    let isEnabled: Bool

    init(isEnabled: Bool = true, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(isEnabled ? LiquidGlass.Colors.interactiveTint : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .glassEffect(
            isEnabled ? .regular.tint(LiquidGlass.Colors.interactiveTint).interactive() : .regular,
            in: .circle
        )
    }
}

// MARK: - Voice Button

/// Microphone button for voice input
struct VoiceButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.title3)
                .foregroundStyle(isListening ? .red : .secondary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isListening ? .regular.tint(.red).interactive() : .regular.interactive(),
            in: .circle
        )
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard glass effect with default corner radius
    func standardGlass() -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidGlass.CornerRadius.lg, style: .continuous))
    }

    /// Apply interactive glass effect
    @ViewBuilder
    func interactiveGlass(tint: Color? = nil) -> some View {
        if let tint {
            self.glassEffect(.regular.tint(tint).interactive(), in: RoundedRectangle(cornerRadius: LiquidGlass.CornerRadius.lg, style: .continuous))
        } else {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: LiquidGlass.CornerRadius.lg, style: .continuous))
        }
    }

    /// Apply pill-shaped glass effect
    func pillGlass() -> some View {
        self.glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
