//
//  SettingsView.swift
//  Anthropod
//
//  Settings window for chat, models, and usage
//

import SwiftUI
import Foundation
import Charts

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

                LabeledContent("Default model", value: defaultModelRef)
                if let name = defaultModelName {
                    LabeledContent("Default name", value: name)
                }
                LabeledContent("Last used", value: sessionModelRef)
                if let name = sessionModelName {
                    LabeledContent("Last used name", value: name)
                }
                Text("Availability depends on gateway auth and provider status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Preferred model", selection: $preferredModelId) {
                    Text("Gateway default (server-selected)").tag("")
                    ForEach(pickerModels) { choice in
                        Text(modelOptionLabel(choice))
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
                } else {
                    Text("Gateway default will use the server’s configured model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var pickerModels: [ModelChoice] {
        var seen = Set<String>()
        return model.models.filter { seen.insert($0.id).inserted }
    }

    private var defaultModelRef: String {
        modelRef(provider: model.defaultModelProvider, id: model.defaultModelId) ?? "Unavailable"
    }

    private var sessionModelRef: String {
        modelRef(provider: model.sessionModelProvider, id: model.sessionModelId) ?? "Not yet used"
    }

    private var defaultModelName: String? {
        modelName(provider: model.defaultModelProvider, id: model.defaultModelId)
    }

    private var sessionModelName: String? {
        modelName(provider: model.sessionModelProvider, id: model.sessionModelId)
    }

    private func modelRef(provider: String?, id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        if let provider, !provider.isEmpty {
            return "\(provider)/\(id)"
        }
        return id
    }

    private func modelName(provider: String?, id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        let match = model.models.first {
            $0.id == id && (provider == nil || $0.provider == provider)
        }
        guard let match else { return nil }
        let display = modelDisplayName(match)
        return display == id ? nil : display
    }

    private func modelDisplayName(_ choice: ModelChoice) -> String {
        choice.name.isEmpty ? choice.id : choice.name
    }

    private func modelOptionLabel(_ choice: ModelChoice) -> String {
        "\(choice.provider) · \(modelDisplayName(choice))"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

private struct UsageSummaryView: View {
    let summary: GatewayCostUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !chartDays.isEmpty {
                Chart {
                    ForEach(chartDays) { day in
                        LineMark(
                            x: .value("Day", day.date),
                            y: .value("Cost", day.cost)
                        )
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Day", day.date),
                            y: .value("Cost", day.cost)
                        )
                    }
                }
                .chartXScale(domain: chartDomain)
                .chartYScale(domain: chartCostDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        if let cost = value.as(Double.self),
                           let label = CostUsageFormatting.formatUsd(cost)
                        {
                            AxisValueLabel(label)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel(Self.chartLabelFormatter.string(from: date))
                        }
                        AxisTick()
                        AxisGridLine()
                    }
                }
                .frame(height: 140)
            }

            UsageCardStatsView(metrics: metrics)
        }
    }

    struct Metric: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let isPrimary: Bool
    }

    private var metrics: [Metric] {
        var list: [Metric] = [
            Metric(
                title: "Cost",
                value: CostUsageFormatting.formatUsd(summary.totals.totalCost) ?? "–",
                isPrimary: true
            ),
            Metric(
                title: "Tokens",
                value: CostUsageFormatting.formatTokenCount(summary.totals.totalTokens) ?? "–",
                isPrimary: true
            ),
            Metric(
                title: "Input",
                value: CostUsageFormatting.formatTokenCount(summary.totals.input) ?? "–",
                isPrimary: false
            ),
            Metric(
                title: "Output",
                value: CostUsageFormatting.formatTokenCount(summary.totals.output) ?? "–",
                isPrimary: false
            )
        ]
        if summary.totals.cacheRead > 0 {
            list.append(
                Metric(
                    title: "Cache read",
                    value: CostUsageFormatting.formatTokenCount(summary.totals.cacheRead) ?? "–",
                    isPrimary: false
                )
            )
        }
        if summary.totals.cacheWrite > 0 {
            list.append(
                Metric(
                    title: "Cache write",
                    value: CostUsageFormatting.formatTokenCount(summary.totals.cacheWrite) ?? "–",
                    isPrimary: false
                )
            )
        }
        return list
    }

    private struct ChartDay: Identifiable {
        let id = UUID()
        let date: Date
        let cost: Double
    }

    private var chartDays: [ChartDay] {
        let mapped = summary.daily.compactMap { entry -> ChartDay? in
            guard let date = Self.inputDateFormatter.date(from: entry.date) else { return nil }
            return ChartDay(
                date: date,
                cost: entry.totalCost
            )
        }
        let sorted = mapped.sorted { $0.date < $1.date }
        return Array(sorted.suffix(14))
    }

    private var chartCostDomain: ClosedRange<Double> {
        let values = chartDays.map(\.cost)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        let range = maxValue - minValue
        let minRange = max(0.01, maxValue * 0.2)
        let effectiveRange = max(range, minRange)
        let mid = (minValue + maxValue) / 2.0
        var lower = mid - (effectiveRange / 2.0)
        var upper = mid + (effectiveRange / 2.0)
        if lower < 0 {
            upper += -lower
            lower = 0
        }
        if lower == upper {
            upper = lower + minRange
        }
        return lower...upper
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let chartLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
    private var chartDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -13, to: end) ?? end
        return start...end
    }
}

private struct UsageCardStatsView: View {
    let metrics: [UsageSummaryView.Metric]

    var body: some View {
        let columns = [
            GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 8, alignment: .leading)
        ]

        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(metric.isPrimary ? .headline.weight(.semibold) : .subheadline)
                        .monospacedDigit()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
