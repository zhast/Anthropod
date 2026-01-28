//
//  MenuBarContentView.swift
//  Anthropod
//
//  Minimal menu bar content for quick status and navigation
//

import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @State private var gateway = GatewayService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openChat()
        } label: {
            Label("Open Chat", systemImage: "bubble.left.and.bubble.right")
        }

        Button {
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }

        Divider()

        Label(statusText, systemImage: statusSymbol)
            .disabled(true)

        if let detail = statusDetail {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button {
            Task { await gateway.connect() }
        } label: {
            Label("Reconnect Gateway", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(gateway.isConnecting)

        Divider()

        Button("Quit Anthropod") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusText: String {
        if gateway.isConnecting { return "Gateway Connecting…" }
        if gateway.isConnected { return "Gateway Connected" }
        return "Gateway Offline"
    }

    private var statusSymbol: String {
        if gateway.isConnecting { return "arrow.triangle.2.circlepath" }
        if gateway.isConnected { return "checkmark.circle" }
        return "xmark.circle"
    }

    private var statusDetail: String? {
        if let error = gateway.connectionError, !error.isEmpty {
            return error
        }
        if gateway.isConnected {
            return "Session \(gateway.mainSessionKey)"
        }
        return nil
    }

    @MainActor
    private func openChat() {
        openWindow(id: "chat")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func openSettings() {
        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
