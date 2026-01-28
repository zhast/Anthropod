//
//  LiquidGlassTokens.swift
//  Anthropod
//
//  Design system tokens for Liquid Glass (macOS 26 Tahoe)
//

import SwiftUI

enum LiquidGlass {
    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        /// Breathing room between messages
        static let messagePadding: CGFloat = 16
        static let messageGroupSpacing: CGFloat = 6
        static let messageStackSpacing: CGFloat = 4
        static let messageGroupGap: CGFloat = 12

        /// Minimum space on opposite side of message bubble
        static let bubbleMinMargin: CGFloat = 60

        /// Input bar insets from window edge
        static let inputBarHorizontal: CGFloat = 16
        static let inputBarBottom: CGFloat = 12

        /// Padding inside input bar
        static let inputBarPaddingH: CGFloat = 16
        static let inputBarPaddingV: CGFloat = 12

        /// Space reserved at bottom of scroll for input bar
        static let scrollBottomInset: CGFloat = 80
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999

        /// Message bubble corner radius
        static let bubble: CGFloat = 16

        /// Input bar corner radius
        static let inputBar: CGFloat = 20
    }

    // MARK: - Animation

    enum Animation {
        /// Standard glass morph duration
        static let morphDuration: Double = 0.35

        /// Spring response for interactive elements
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.7

        /// Quick feedback animations
        static let quickDuration: Double = 0.2

        static var spring: SwiftUI.Animation {
            .spring(response: springResponse, dampingFraction: springDamping)
        }

        static var quick: SwiftUI.Animation {
            .easeOut(duration: quickDuration)
        }

        static var morph: SwiftUI.Animation {
            .easeInOut(duration: morphDuration)
        }
    }

    // MARK: - Colors

    enum Colors {
        /// User message bubble background
        static let userBubble = Color.accentColor.opacity(0.15)

        /// Assistant message bubble background
        static let assistantBubble = Color.secondary.opacity(0.08)

        /// Subtle text color for secondary content
        static let secondaryText = Color.secondary

        /// Tint for interactive glass elements (send button)
        static let interactiveTint = Color.blue
    }

    // MARK: - Typography

    enum Typography {
        static let messageBody: Font = .body
        static let inputPlaceholder: Font = .body
        static let timestamp: Font = .caption
    }

    // MARK: - Window

    enum Window {
        static let minWidth: CGFloat = 400
        static let minHeight: CGFloat = 500
        static let defaultWidth: CGFloat = 480
        static let defaultHeight: CGFloat = 700
    }
}
