# Liquid Glass Mac App - Complete Rewrite Plan

## Overview

Create a new Mac app from scratch using Apple's native Liquid Glass design (macOS 26 Tahoe) to replace the existing Moltbot Mac app, with focus on decluttering the chat UI.

## Target

- macOS 26+ (Tahoe) - use native `.glassEffect()` APIs
- SwiftUI-first - minimize AppKit usage
- Focus: Clean, uncluttered chat experience

## Current App Analysis

The existing app in `apps/macos/` has 193 Swift files with:

- Menu bar presence with status icon
- Web chat panel (cluttered)
- Voice wake / talk mode
- Canvas (WKWebView agent UI)
- Settings (11 tabs)
- Onboarding wizard
- Approval workflows
- Gateway WebSocket communication

User's pain point: Chat is cluttered.

---

## Project Structure (Actual)

Location: `/Users/zhast/Documents/GitHub/anthropod/Anthropod/`

```
Anthropod/
├── Anthropod/
│   ├── AnthropodApp.swift              # @main entry (exists - modify)
│   ├── ContentView.swift               # Replace with ChatView
│   ├── Item.swift                      # SwiftData model (replace with Message)
│   ├── Assets.xcassets/
│   │
│   │ -- New files to create --
│   ├── Design/
│   │   ├── LiquidGlassTokens.swift     # Spacing, timing constants
│   │   └── GlassComponents.swift       # Reusable glass views
│   ├── Chat/
│   │   ├── ChatView.swift              # Main chat - CLEAN design
│   │   ├── MessageBubble.swift         # Minimal message styling
│   │   ├── ChatInputBar.swift          # Glass input field
│   │   └── Message.swift               # Message model (SwiftData)
│   └── (future: Voice/, Settings/, Gateway/)
│
├── Anthropod.xcodeproj/
├── AnthropodTests/
└── AnthropodUITests/
```

---

## Liquid Glass API Usage (macOS 26)

### Core Modifiers

```swift
// Basic glass effect
.glassEffect()  // Default: .regular variant

// Glass variants
.glassEffect(.regular)  // Standard UI elements
.glassEffect(.clear)    // Over media/photos
.glassEffect(.identity) // Disabled state

// With custom shape
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
.glassEffect(.regular, in: .capsule)

// Tinted glass (for CTAs)
.glassEffect(.regular.tint(.blue))

// Interactive (bouncy, shimmering)
.glassEffect(.regular.interactive())
```

### GlassEffectContainer (for grouped elements)

```swift
GlassEffectContainer(spacing: 12) {
    HStack {
        Button("Send") { }.glassEffect()
        Button("Voice") { }.glassEffect()
    }
}
```

### Morphing Transitions

```swift
@Namespace private var namespace

GlassEffectContainer {
    if showingTools {
        ToolbarView()
            .glassEffect()
            .glassEffectID("tools", in: namespace)
    }
}
```

---

## Chat UI Redesign (Priority #1)

### Current Problems (cluttered)

- Too many visible controls
- Dense message layout
- Distracting chrome
- Settings mixed with chat

### New Design Principles

1. Content first - messages are primary, glass controls float above
2. Progressive disclosure - hide tools until needed
3. Breathing room - generous spacing between messages
4. Minimal chrome - glass toolbar appears on hover/scroll

### Chat View Structure

```swift
struct ChatView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content layer (NOT glass)
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80) // Space for input
            }

            // Navigation layer (glass)
            GlassEffectContainer {
                ChatInputBar()
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}
```

### Message Bubble (Clean)

```swift
struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 60) }

            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    message.isFromUser
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !message.isFromUser { Spacer(minLength: 60) }
        }
    }
}
```

### Input Bar (Glass)

```swift
struct ChatInputBar: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

---

## Implementation Phases

### Phase 1: Design System Foundation

Create new files in `Anthropod/Anthropod/Design/`:

- `LiquidGlassTokens.swift` - spacing, timing, shadow constants
- `GlassComponents.swift` - reusable glass modifiers and views

### Phase 2: Chat UI (Core Focus - Priority)

- `ChatView.swift` - clean message list
- `MessageBubble.swift` - minimal bubbles, no clutter
- `ChatInputBar.swift` - glass input with send button
- `ChatViewModel.swift` - message state management
- Connect to gateway WebSocket (port from existing)

### Phase 3: Voice & Overlays

- `VoiceOverlay.swift` - glass transcription HUD
- `TalkModeView.swift` - glass orb for voice mode
- Voice wake integration (port from existing)

### Phase 4: Menu Bar & Settings

- `MenuBarView.swift` - status icon and dropdown
- `SettingsView.swift` - simplified, glass-styled tabs
- Gateway configuration UI

### Phase 5: Remaining Features

- Onboarding flow
- Approval dialogs
- Canvas/WebView integration
- Session management

---

## Key Design Decisions

### 1. Glass Only for Navigation Layer

Per Apple guidelines: "Liquid Glass applies exclusively to the navigation layer that floats above app content. Never apply to content itself."

- Glass: Input bar, toolbar, overlays, settings chrome
- Not glass: Message bubbles, content areas, lists

### 2. Declutter Strategy

- Hide session picker until clicked
- Collapse tools into overflow menu
- Remove redundant status indicators
- Single-purpose views (chat is just chat)

### 3. Accessibility

Let system handle automatically:

- Reduced Transparency -> increased frosting
- Increased Contrast -> stark colors/borders
- Reduced Motion -> toned-down animations

---

## Verification Plan

1. Build: Open `Anthropod.xcodeproj` in Xcode, build (Cmd+B)
2. Run: Launch app (Cmd+R), verify window appears with chat UI
3. Chat test: Type a message, send, verify clean layout and glass input bar
4. Glass test: Resize window, verify glass effects adapt to background
5. Dark mode: Toggle appearance in System Settings, verify both work
6. Accessibility: Enable "Reduce Transparency" in System Settings, verify fallback

---

## Dependencies

Phase 1-2 (Chat UI): No external dependencies needed

- macOS 26 native `.glassEffect()` API
- SwiftData for message persistence

Future phases: May add for gateway connection

- URLSession WebSocket (built-in)
- Sparkle (auto-updates)

---

## Sources

- https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/videos/play/wwdc2025/323/
- https://github.com/conorluddy/LiquidGlassReference
