//
//  AnthropodApp.swift
//  Anthropod
//
//  Created by Steven Zhang on 1/27/26.
//

import SwiftUI
import SwiftData

@main
struct AnthropodApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Message.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ChatView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .defaultSize(
            width: LiquidGlass.Window.defaultWidth,
            height: LiquidGlass.Window.defaultHeight
        )
        .commands {
            SettingsCommands()
        }

        Window("Anthropod Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 700, height: 480)
    }
}

private struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
