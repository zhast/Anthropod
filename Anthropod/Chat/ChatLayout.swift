//
//  ChatLayout.swift
//  Anthropod
//
//  Layout tuning for compact vs. standard chat density
//

import SwiftUI

struct ChatLayout: Equatable {
    let isCompact: Bool

    var listHorizontalPadding: CGFloat {
        isCompact ? 16 : LiquidGlass.Spacing.lg
    }

    var listTopPadding: CGFloat {
        isCompact ? 12 : LiquidGlass.Spacing.lg
    }

    var groupGap: CGFloat {
        isCompact ? 8 : LiquidGlass.Spacing.messageGroupGap
    }

    var stackSpacing: CGFloat {
        isCompact ? 2 : LiquidGlass.Spacing.messageStackSpacing
    }

    var bubblePaddingH: CGFloat {
        isCompact ? 12 : LiquidGlass.Spacing.md
    }

    var bubblePaddingV: CGFloat {
        isCompact ? 8 : LiquidGlass.Spacing.sm
    }

    var bubbleMinMargin: CGFloat {
        isCompact ? 48 : LiquidGlass.Spacing.bubbleMinMargin
    }

    var timestampOffsetY: CGFloat {
        isCompact ? -10 : -14
    }

    var dividerVerticalPadding: CGFloat {
        isCompact ? 6 : LiquidGlass.Spacing.xs
    }
}
