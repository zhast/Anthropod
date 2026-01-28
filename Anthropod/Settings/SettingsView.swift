//
//  SettingsView.swift
//  Anthropod
//
//  Settings window for chat, models, and usage
//

import SwiftUI
import Foundation

struct SettingsView: View {
    @State private var model = SettingsViewModel()

    @AppStorage(AnthropodDefaults.compactLayout) private var compactLayout = false
    @AppStorage(AnthropodDefaults.compactMaxLines) private var compactMaxLines = 400
    @AppStorage(AnthropodDefaults.preferredModelId) private var preferredModelId = ""

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalPane
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                chatPane
            }
            Tab("Models", systemImage: "cpu") {
                modelsPane
            }
            Tab("Usage", systemImage: "chart.bar") {
                usagePane
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 700, minHeight: 480)
        .task {
            await model.refreshAll()
        }
        .onChange(of: preferredModelId) { _, newValue in
            Task {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                await model.applyModel(trimmed.isEmpty ? nil : trimmed)
            }
        }
    }

    private var generalPane: some View {
        Form {
            Section("Gateway") {
                LabeledContent("Status", value: model.connectionStatusText)
                if let detail = model.connectionStatusDetail {
                    LabeledContent("Session", value: detail)
                }
                Button("Reconnect") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .formStyle(.grouped)
    }

    private var chatPane: some View {
        Form {
            Section("Chat History") {
                Stepper(value: $compactMaxLines, in: 100...2000, step: 50) {
                    LabeledContent("Compact target", value: "\(compactMaxLines) lines")
                }
                Button("Compact current session") {
                    Task { await model.compactSession(maxLines: compactMaxLines) }
                }
                if let status = model.compactStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Layout") {
                Toggle("Compact message layout", isOn: $compactLayout)
                Text("Use compact layout for tighter spacing and smaller bubble padding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var modelsPane: some View {
        Form {
            Section("Model Selection") {
                if model.isLoadingModels {
                    ProgressView("Loading models…")
                }

                Picker("Default model", selection: $preferredModelId) {
                    Text("Gateway default").tag("")
                    ForEach(model.models) { choice in
                        Text(choice.name.isEmpty ? choice.id : choice.name)
                            .tag(choice.id)
                    }
                }
                .pickerStyle(.menu)

                if let choice = selectedModelChoice {
                    LabeledContent("Provider", value: choice.provider)
                    if let context = choice.contextWindow {
                        LabeledContent("Context", value: "\(context) tokens")
                    }
                    if let reasoning = choice.reasoning {
                        LabeledContent("Reasoning", value: reasoning ? "Supported" : "No")
                    }
                }

                if let error = model.modelError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reload models") {
                    Task { await model.refreshModels() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var usagePane: some View {
        Form {
            Section("Usage") {
                if model.isLoadingUsage {
                    ProgressView("Loading usage…")
                } else if let summary = model.usageSummary {
                    UsageSummaryView(summary: summary)
                } else {
                    Text(model.usageError ?? "No usage data available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh usage") {
                    Task { await model.refreshUsage() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var selectedModelChoice: ModelChoice? {
        guard !preferredModelId.isEmpty else { return nil }
        return model.models.first { $0.id == preferredModelId }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

private struct UsageSummaryView: View {
    let summary: GatewayCostUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Total cost", value: CostUsageFormatting.formatUsd(summary.totals.totalCost) ?? "–")
            LabeledContent("Total tokens", value: CostUsageFormatting.formatTokenCount(summary.totals.totalTokens) ?? "–")
            LabeledContent("Input", value: CostUsageFormatting.formatTokenCount(summary.totals.input) ?? "–")
            LabeledContent("Output", value: CostUsageFormatting.formatTokenCount(summary.totals.output) ?? "–")
            LabeledContent("Cache read", value: CostUsageFormatting.formatTokenCount(summary.totals.cacheRead) ?? "–")
            LabeledContent("Cache write", value: CostUsageFormatting.formatTokenCount(summary.totals.cacheWrite) ?? "–")

            if let updated = updatedAtText {
                Text("Updated \(updated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !summary.daily.isEmpty {
                Divider()
                Text("Recent days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(summary.daily.prefix(7), id: \.date) { entry in
                    HStack {
                        Text(entry.date)
                            .font(.caption)
                        Spacer()
                        Text(CostUsageFormatting.formatUsd(entry.totalCost) ?? "–")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var updatedAtText: String? {
        let seconds = summary.updatedAt > 10_000_000_000 ? summary.updatedAt / 1000 : summary.updatedAt
        guard seconds.isFinite else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
