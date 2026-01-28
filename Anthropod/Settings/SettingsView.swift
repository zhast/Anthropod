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
    @State private var workspaceDocSelection = "AGENTS.md"

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
            Tab("Files", systemImage: "doc.text") {
                configPane
            }
            Tab("Docs", systemImage: "doc.richtext") {
                docsPane
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

    private var configPane: some View {
        Form {
            Section("Config") {
                ConfigUIEditor(
                    draft: model.configDraft,
                    error: model.configDraftError,
                    hasChanges: model.configDraftHasChanges,
                    onUpdate: { updated in
                        model.updateConfigDraft { $0 = updated }
                    },
                    onSave: { Task { await model.saveConfigFile() } },
                    onRevert: { model.revertConfigEdits() }
                )
                DisclosureGroup("Raw Config") {
                    ConfigFileEditor(
                        title: "Config",
                        subtitle: model.configPath,
                        text: $model.configText,
                        isLoading: model.isLoadingConfig,
                        error: model.configError,
                        hasChanges: model.configText != model.configOriginalText,
                        onFormat: {
                            model.formatConfigJson()
                        },
                        onReload: { Task { await model.loadConfigFile() } },
                        onRevert: { model.revertConfigEdits() },
                        onSave: { Task { await model.saveConfigFile() } }
                    )
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .task {
            await model.refreshConfigFiles()
        }
    }

    private var docsPane: some View {
        VStack(spacing: 12) {
            DocSegmentedPicker(selection: $workspaceDocSelection, docs: workspaceDocs)
                .padding(.horizontal)
                .padding(.top, 8)

            Form {
                Section {
                    ConfigFileEditor(
                        title: selectedWorkspaceDoc?.title ?? "Workspace Doc",
                        subtitle: model.workspaceDocPath,
                        text: $model.workspaceDocText,
                        isLoading: model.isLoadingWorkspaceDoc,
                        error: model.workspaceDocError,
                        hasChanges: model.workspaceDocText != model.workspaceDocOriginalText,
                        onFormat: nil,
                        onReload: { Task { await model.loadWorkspaceDoc(relativePath: workspaceDocSelection) } },
                        onRevert: { model.revertWorkspaceDocEdits() },
                        onSave: { Task { await model.saveWorkspaceDoc(relativePath: workspaceDocSelection) } }
                    )
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await model.loadWorkspaceDoc(relativePath: workspaceDocSelection)
        }
        .onChange(of: workspaceDocSelection) { _, newValue in
            Task { await model.loadWorkspaceDoc(relativePath: newValue) }
        }
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

    private var selectedWorkspaceDoc: WorkspaceDocSpec? {
        workspaceDocs.first { $0.relativePath == workspaceDocSelection }
    }

    private var workspaceDocs: [WorkspaceDocSpec] {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let todayString = Self.memoryDateFormatter.string(from: today)
        let yesterdayString = Self.memoryDateFormatter.string(from: yesterday)
        return [
            WorkspaceDocSpec(title: "AGENTS.md", toolbarTitle: "Agents", relativePath: "AGENTS.md"),
            WorkspaceDocSpec(title: "SOUL.md", toolbarTitle: "Soul", relativePath: "SOUL.md"),
            WorkspaceDocSpec(title: "USER.md", toolbarTitle: "User", relativePath: "USER.md"),
            WorkspaceDocSpec(title: "MEMORY.md", toolbarTitle: "Memory", relativePath: "MEMORY.md"),
            WorkspaceDocSpec(title: "HEARTBEAT.md", toolbarTitle: "Heartbeat", relativePath: "HEARTBEAT.md"),
            WorkspaceDocSpec(title: "TOOLS.md", toolbarTitle: "Tools", relativePath: "TOOLS.md"),
            WorkspaceDocSpec(title: "IDENTITY.md", toolbarTitle: "Identity", relativePath: "IDENTITY.md"),
            WorkspaceDocSpec(title: "BOOTSTRAP.md", toolbarTitle: "Bootstrap", relativePath: "BOOTSTRAP.md"),
            WorkspaceDocSpec(
                title: "Memory (Today \(todayString))",
                toolbarTitle: "Today",
                relativePath: "memory/\(todayString).md"
            ),
            WorkspaceDocSpec(
                title: "Memory (Yesterday \(yesterdayString))",
                toolbarTitle: "Yesterday",
                relativePath: "memory/\(yesterdayString).md"
            )
        ]
    }

    private static let memoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct WorkspaceDocSpec: Identifiable, Hashable {
    let id: String
    let title: String
    let toolbarTitle: String
    let relativePath: String

    init(title: String, toolbarTitle: String, relativePath: String) {
        self.id = relativePath
        self.title = title
        self.toolbarTitle = toolbarTitle
        self.relativePath = relativePath
    }
}

private struct DocSegmentedPicker: View {
    @Binding var selection: String
    let docs: [WorkspaceDocSpec]

    var body: some View {
        let firstRow = docs.prefix(5)
        let secondRow = docs.dropFirst(5)

        VStack(alignment: .leading, spacing: 10) {
            Picker("Workspace Docs", selection: $selection) {
                ForEach(Array(firstRow)) { doc in
                    Text(doc.toolbarTitle).tag(doc.relativePath)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !secondRow.isEmpty {
                Picker("More Docs", selection: $selection) {
                    ForEach(Array(secondRow)) { doc in
                        Text(doc.toolbarTitle).tag(doc.relativePath)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

private struct ConfigUIEditor: View {
    let draft: SettingsViewModel.ConfigDraft?
    let error: String?
    let hasChanges: Bool
    let onUpdate: (SettingsViewModel.ConfigDraft) -> Void
    let onSave: () -> Void
    let onRevert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let draft {
                HStack(spacing: 12) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(!hasChanges)
                    Button("Revert") {
                        onRevert()
                    }
                    .disabled(!hasChanges)
                }

                Group {
                    Toggle("Enable browser", isOn: binding(draft, keyPath: \.browserEnabled))

                    LabeledContent("Workspace") {
                        TextField("Path", text: binding(draft, keyPath: \.workspace))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }

                    LabeledContent("Max concurrent") {
                        TextField("Max", text: maxConcurrentBinding(draft))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }
                }

                Divider()

                Group {
                    LabeledContent("Primary model") {
                        if draft.modelChoices.isEmpty {
                            TextField("Model id", text: binding(draft, keyPath: \.modelPrimary))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                        } else {
                            Picker("Primary", selection: binding(draft, keyPath: \.modelPrimary)) {
                                ForEach(primaryOptions(for: draft), id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fallbacks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if draft.modelFallbacks.isEmpty {
                            Text("None")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(draft.modelFallbacks, id: \.self) { fallback in
                                HStack {
                                    Text(fallback)
                                        .font(.caption)
                                    Spacer()
                                    Button {
                                        removeFallback(fallback, from: draft)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Menu("Add fallback") {
                            ForEach(fallbackOptions(for: draft), id: \.self) { model in
                                Button(model) {
                                    addFallback(model, to: draft)
                                }
                            }
                        }
                        .disabled(fallbackOptions(for: draft).isEmpty)
                    }
                }

                Divider()

                Group {
                    LabeledContent("Context pruning") {
                        TextField("Mode", text: binding(draft, keyPath: \.contextPruningMode))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                    }
                    LabeledContent("Pruning TTL") {
                        TextField("TTL", text: binding(draft, keyPath: \.contextPruningTtl))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                    LabeledContent("Compaction") {
                        TextField("Mode", text: binding(draft, keyPath: \.compactionMode))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                    }
                    LabeledContent("Heartbeat") {
                        TextField("Every", text: binding(draft, keyPath: \.heartbeatEvery))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                }

                if !draft.authProfiles.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auth profiles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(draft.authProfiles, id: \.id) { profile in
                            HStack {
                                Text(profile.id)
                                    .font(.caption)
                                Spacer()
                                Text(profile.mode ?? "unknown")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Config UI unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding<T>(
        _ draft: SettingsViewModel.ConfigDraft,
        keyPath: WritableKeyPath<SettingsViewModel.ConfigDraft, T>
    ) -> Binding<T> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                var copy = draft
                copy[keyPath: keyPath] = newValue
                onUpdate(copy)
            }
        )
    }

    private func maxConcurrentBinding(_ draft: SettingsViewModel.ConfigDraft) -> Binding<String> {
        Binding(
            get: { draft.maxConcurrent.map(String.init) ?? "" },
            set: { newValue in
                var copy = draft
                if let value = Int(newValue) {
                    copy.maxConcurrent = value
                } else {
                    copy.maxConcurrent = nil
                }
                onUpdate(copy)
            }
        )
    }

    private func primaryOptions(for draft: SettingsViewModel.ConfigDraft) -> [String] {
        var options = draft.modelChoices
        if !draft.modelPrimary.isEmpty && !options.contains(draft.modelPrimary) {
            options.insert(draft.modelPrimary, at: 0)
        }
        return options
    }

    private func fallbackOptions(for draft: SettingsViewModel.ConfigDraft) -> [String] {
        let used = Set(draft.modelFallbacks + [draft.modelPrimary])
        return draft.modelChoices.filter { !used.contains($0) }
    }

    private func removeFallback(_ fallback: String, from draft: SettingsViewModel.ConfigDraft) {
        var copy = draft
        copy.modelFallbacks.removeAll { $0 == fallback }
        onUpdate(copy)
    }

    private func addFallback(_ fallback: String, to draft: SettingsViewModel.ConfigDraft) {
        var copy = draft
        if !copy.modelFallbacks.contains(fallback) {
            copy.modelFallbacks.append(fallback)
        }
        onUpdate(copy)
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

private struct ConfigFileEditor: View {
    let title: String
    let subtitle: String?
    @Binding var text: String
    let isLoading: Bool
    let error: String?
    let hasChanges: Bool
    let onFormat: (() -> Void)?
    let onReload: () -> Void
    let onRevert: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .textSelection(.enabled)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack(spacing: 12) {
                if let onFormat {
                    Button("Format JSON") {
                        onFormat()
                    }
                    .disabled(isLoading)
                }
                Button("Reload") {
                    onReload()
                }
                .disabled(isLoading)
                Button("Revert") {
                    onRevert()
                }
                .disabled(!hasChanges || isLoading)
                Button("Save") {
                    onSave()
                }
                .disabled(!hasChanges || isLoading)
                Spacer()
                if let error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
