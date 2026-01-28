//
//  SettingsViewModel.swift
//  Anthropod
//
//  Shared settings data + gateway interactions
//

import Foundation

@MainActor
@Observable
final class SettingsViewModel {
    private let gateway = GatewayService.shared

    var models: [ModelChoice] = []
    var isLoadingModels = false
    var modelError: String?
    var defaultModelProvider: String?
    var defaultModelId: String?
    var defaultModelContextTokens: Int?
    var sessionModelProvider: String?
    var sessionModelId: String?
    var sessionModelContextTokens: Int?

    var usageSummary: GatewayCostUsageSummary?
    var isLoadingUsage = false
    var usageError: String?

    var compactStatus: String?
    var configPath: String?
    var configText = ""
    var configOriginalText = ""
    var isLoadingConfig = false
    var configError: String?
    var configDraft: ConfigDraft?
    var configDraftError: String?
    var configDraftOriginal: ConfigDraft?
    private var configDocument: [String: Any] = [:]

    var agentsPath: String?
    var agentsText = ""
    var agentsOriginalText = ""
    var isLoadingAgents = false
    var agentsError: String?
    var workspaceDocPath: String?
    var workspaceDocText = ""
    var workspaceDocOriginalText = ""
    var isLoadingWorkspaceDoc = false
    var workspaceDocError: String?

    func refreshAll() async {
        await ensureConnected()
        await refreshModels()
        await refreshModelStatus()
        await refreshUsage()
        await refreshConfigFiles()
    }

    func refreshModels() async {
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }

        do {
            await ensureConnected()
            let loaded = try await gateway.modelsList()
            models = loaded.sorted {
                if $0.provider != $1.provider {
                    return $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            modelError = error.localizedDescription
            models = []
        }
    }

    func refreshModelStatus() async {
        do {
            await ensureConnected()
            let status = try await gateway.sessionModelSnapshot(sessionKey: gateway.mainSessionKey)
            defaultModelProvider = status.defaultProvider
            defaultModelId = status.defaultModel
            defaultModelContextTokens = status.defaultContextTokens
            sessionModelProvider = status.sessionProvider
            sessionModelId = status.sessionModel
            sessionModelContextTokens = status.sessionContextTokens
        } catch {
            defaultModelProvider = nil
            defaultModelId = nil
            defaultModelContextTokens = nil
            sessionModelProvider = nil
            sessionModelId = nil
            sessionModelContextTokens = nil
        }
    }

    func refreshUsage() async {
        isLoadingUsage = true
        usageError = nil
        defer { isLoadingUsage = false }

        do {
            await ensureConnected()
            usageSummary = try await gateway.usageCostSummary()
        } catch {
            usageError = error.localizedDescription
            usageSummary = nil
        }
    }

    func applyModel(_ modelId: String?) async {
        do {
            await ensureConnected()
            try await gateway.patchSessionModel(modelId: modelId)
            compactStatus = nil
            await refreshModelStatus()
        } catch {
            modelError = error.localizedDescription
        }
    }

    func compactSession(maxLines: Int) async {
        do {
            await ensureConnected()
            try await gateway.compactSession(maxLines: maxLines)
            compactStatus = "Compacted chat history"
        } catch {
            compactStatus = error.localizedDescription
        }
    }

    func refreshConfigFiles() async {
        await loadConfigFile()
        await loadAgentsFile()
    }

    func loadConfigFile() async {
        isLoadingConfig = true
        configError = nil
        defer { isLoadingConfig = false }

        let url = ClawdbotPaths.configURL
        configPath = url.path
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            if let formatted = Self.prettyPrintedJson(from: text) {
                configText = formatted
                configOriginalText = formatted
            } else {
                configText = text
                configOriginalText = text
            }
            if let document = Self.jsonDocument(from: configText) {
                configDocument = document
                let draft = Self.buildConfigDraft(from: document)
                configDraft = draft
                configDraftOriginal = draft
                configDraftError = nil
            } else {
                configDraft = nil
                configDraftOriginal = nil
                configDraftError = "Config JSON is invalid."
            }
        } catch {
            configError = "Unable to load config: \(error.localizedDescription)"
            configText = ""
            configOriginalText = ""
            configDraft = nil
            configDraftOriginal = nil
            configDraftError = nil
        }
    }

    func saveConfigFile() async {
        let url = ClawdbotPaths.configURL
        configPath = url.path
        if let formatted = Self.prettyPrintedJson(from: configText) {
            configText = formatted
            if let document = Self.jsonDocument(from: formatted) {
                configDocument = document
                configDraft = Self.buildConfigDraft(from: document)
                configDraftError = nil
            }
        } else {
            configError = "Config JSON is invalid."
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: ClawdbotPaths.stateDirURL,
                withIntermediateDirectories: true
            )
            try configText.write(to: url, atomically: true, encoding: .utf8)
            configOriginalText = configText
            configDraftOriginal = configDraft
            configError = nil
        } catch {
            configError = "Unable to save config: \(error.localizedDescription)"
        }
    }

    func updateConfigDraft(_ mutate: (inout ConfigDraft) -> Void) {
        guard var draft = configDraft else { return }
        mutate(&draft)
        if draft == configDraft {
            return
        }
        configDraft = draft
        syncConfigTextFromDraft(draft)
    }

    func formatConfigJson() {
        guard let formatted = Self.prettyPrintedJson(from: configText) else {
            configError = "Config JSON is invalid."
            return
        }
        configText = formatted
        if let document = Self.jsonDocument(from: formatted) {
            configDocument = document
            configDraft = Self.buildConfigDraft(from: document)
            configDraftError = nil
        }
    }

    func revertConfigEdits() {
        configText = configOriginalText
        configError = nil
        if let document = Self.jsonDocument(from: configOriginalText) {
            configDocument = document
            let draft = Self.buildConfigDraft(from: document)
            configDraft = draft
            configDraftOriginal = draft
            configDraftError = nil
        } else {
            configDraft = nil
            configDraftOriginal = nil
            configDraftError = "Config JSON is invalid."
        }
    }

    func loadAgentsFile() async {
        isLoadingAgents = true
        agentsError = nil
        defer { isLoadingAgents = false }

        let url = agentsFileURL()
        agentsPath = url.path
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                agentsText = text
                agentsOriginalText = text
            } catch {
                agentsError = "Unable to load agents: \(error.localizedDescription)"
                agentsText = ""
                agentsOriginalText = ""
            }
        } else {
            agentsError = "File not found"
            agentsText = ""
            agentsOriginalText = ""
        }
    }

    func saveAgentsFile() async {
        let url = agentsFileURL()
        agentsPath = url.path
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try agentsText.write(to: url, atomically: true, encoding: .utf8)
            agentsOriginalText = agentsText
            agentsError = nil
        } catch {
            agentsError = "Unable to save agents: \(error.localizedDescription)"
        }
    }

    func revertAgentsEdits() {
        agentsText = agentsOriginalText
        agentsError = nil
    }

    var configDraftHasChanges: Bool {
        guard let configDraft, let configDraftOriginal else { return false }
        return configDraft != configDraftOriginal
    }

    func loadWorkspaceDoc(relativePath: String) async {
        isLoadingWorkspaceDoc = true
        workspaceDocError = nil
        defer { isLoadingWorkspaceDoc = false }

        guard let baseURL = workspaceBaseURL() else {
            workspaceDocPath = nil
            workspaceDocText = ""
            workspaceDocOriginalText = ""
            workspaceDocError = "Workspace path is not set."
            return
        }

        let url = baseURL.appendingPathComponent(relativePath)
        workspaceDocPath = url.path
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                workspaceDocText = text
                workspaceDocOriginalText = text
            } catch {
                workspaceDocError = "Unable to load file: \(error.localizedDescription)"
                workspaceDocText = ""
                workspaceDocOriginalText = ""
            }
        } else {
            workspaceDocText = ""
            workspaceDocOriginalText = ""
            workspaceDocError = "File not found. Save to create it."
        }
    }

    func saveWorkspaceDoc(relativePath: String) async {
        guard let baseURL = workspaceBaseURL() else {
            workspaceDocError = "Workspace path is not set."
            return
        }
        let url = baseURL.appendingPathComponent(relativePath)
        workspaceDocPath = url.path
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try workspaceDocText.write(to: url, atomically: true, encoding: .utf8)
            workspaceDocOriginalText = workspaceDocText
            workspaceDocError = nil
        } catch {
            workspaceDocError = "Unable to save file: \(error.localizedDescription)"
        }
    }

    func revertWorkspaceDocEdits() {
        workspaceDocText = workspaceDocOriginalText
        workspaceDocError = nil
    }

    private func agentsFileURL() -> URL {
        if let workspace = configDraft?.workspace, !workspace.isEmpty {
            let base = URL(fileURLWithPath: workspace, isDirectory: true)
            let preferred = base.appendingPathComponent("AGENTS.md")
            if FileManager.default.fileExists(atPath: preferred.path) {
                return preferred
            }
            let fallback = base.appendingPathComponent("agents.md")
            if FileManager.default.fileExists(atPath: fallback.path) {
                return fallback
            }
            return preferred
        }
        return ClawdbotPaths.agentsURL
    }

    private func workspaceBaseURL() -> URL? {
        guard let workspace = configDraft?.workspace, !workspace.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: workspace, isDirectory: true)
    }

    var connectionStatusText: String {
        if gateway.isConnecting { return "Connecting" }
        if let error = gateway.connectionError, !error.isEmpty { return "Error" }
        return gateway.isConnected ? "Connected" : "Offline"
    }

    var connectionStatusDetail: String? {
        if let error = gateway.connectionError, !error.isEmpty { return error }
        return gateway.isConnected ? gateway.mainSessionKey : nil
    }

    private func ensureConnected() async {
        if !gateway.isConnected && !gateway.isConnecting {
            await gateway.connect()
        }
    }
}

extension SettingsViewModel {
    nonisolated static func prettyPrintedJson(from text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            let formatted = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            return String(data: formatted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    nonisolated static func prettyPrintedJson(from object: Any) -> String? {
        do {
            let formatted = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            return String(data: formatted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    nonisolated static func jsonDocument(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            return object as? [String: Any]
        } catch {
            return nil
        }
    }

    private func syncConfigTextFromDraft(_ draft: ConfigDraft) {
        var document = configDocument
        Self.applyConfigDraft(draft, to: &document)
        configDocument = document
        if let formatted = Self.prettyPrintedJson(from: document) {
            configText = formatted
        }
    }

    nonisolated static func buildConfigDraft(from document: [String: Any]) -> ConfigDraft {
        let browser = (document["browser"] as? [String: Any]) ?? [:]
        let browserEnabled = browser["enabled"] as? Bool

        let agents = (document["agents"] as? [String: Any]) ?? [:]
        let defaults = (agents["defaults"] as? [String: Any]) ?? [:]

        let model = (defaults["model"] as? [String: Any]) ?? [:]
        let modelPrimary = model["primary"] as? String
        let modelFallbacks = model["fallbacks"] as? [String] ?? []

        let modelsDict = (defaults["models"] as? [String: Any]) ?? [:]
        let modelChoices = modelsDict.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let context = (defaults["contextPruning"] as? [String: Any]) ?? [:]
        let contextMode = context["mode"] as? String
        let contextTtl = context["ttl"] as? String

        let compaction = (defaults["compaction"] as? [String: Any]) ?? [:]
        let compactionMode = compaction["mode"] as? String

        let heartbeat = (defaults["heartbeat"] as? [String: Any]) ?? [:]
        let heartbeatEvery = heartbeat["every"] as? String

        let workspace = defaults["workspace"] as? String
        let maxConcurrent = defaults["maxConcurrent"] as? Int ?? (defaults["maxConcurrent"] as? Double).map(Int.init)

        let auth = (document["auth"] as? [String: Any]) ?? [:]
        let profiles = (auth["profiles"] as? [String: Any]) ?? [:]
        let authProfiles = profiles.compactMap { key, value -> ConfigAuthProfile? in
            guard let dict = value as? [String: Any] else { return nil }
            return ConfigAuthProfile(
                id: key,
                provider: dict["provider"] as? String,
                mode: dict["mode"] as? String,
                email: dict["email"] as? String
            )
        }.sorted {
            $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }

        return ConfigDraft(
            browserEnabled: browserEnabled ?? false,
            modelPrimary: modelPrimary ?? "",
            modelFallbacks: modelFallbacks,
            modelChoices: modelChoices,
            contextPruningMode: contextMode ?? "",
            contextPruningTtl: contextTtl ?? "",
            compactionMode: compactionMode ?? "",
            heartbeatEvery: heartbeatEvery ?? "",
            workspace: workspace ?? "",
            maxConcurrent: maxConcurrent,
            authProfiles: authProfiles
        )
    }

    nonisolated static func applyConfigDraft(_ draft: ConfigDraft, to document: inout [String: Any]) {
        var browser = (document["browser"] as? [String: Any]) ?? [:]
        browser["enabled"] = draft.browserEnabled
        document["browser"] = browser

        var agents = (document["agents"] as? [String: Any]) ?? [:]
        var defaults = (agents["defaults"] as? [String: Any]) ?? [:]

        var model = (defaults["model"] as? [String: Any]) ?? [:]
        if !draft.modelPrimary.isEmpty {
            model["primary"] = draft.modelPrimary
        }
        model["fallbacks"] = draft.modelFallbacks
        defaults["model"] = model

        if !draft.workspace.isEmpty {
            defaults["workspace"] = draft.workspace
        }
        if let maxConcurrent = draft.maxConcurrent {
            defaults["maxConcurrent"] = maxConcurrent
        }

        var context = (defaults["contextPruning"] as? [String: Any]) ?? [:]
        if !draft.contextPruningMode.isEmpty {
            context["mode"] = draft.contextPruningMode
        }
        if !draft.contextPruningTtl.isEmpty {
            context["ttl"] = draft.contextPruningTtl
        }
        defaults["contextPruning"] = context

        var compaction = (defaults["compaction"] as? [String: Any]) ?? [:]
        if !draft.compactionMode.isEmpty {
            compaction["mode"] = draft.compactionMode
        }
        defaults["compaction"] = compaction

        var heartbeat = (defaults["heartbeat"] as? [String: Any]) ?? [:]
        if !draft.heartbeatEvery.isEmpty {
            heartbeat["every"] = draft.heartbeatEvery
        }
        defaults["heartbeat"] = heartbeat

        agents["defaults"] = defaults
        document["agents"] = agents
    }

    struct ConfigAuthProfile: Identifiable, Hashable {
        let id: String
        let provider: String?
        let mode: String?
        let email: String?
    }

    struct ConfigDraft: Hashable {
        var browserEnabled: Bool
        var modelPrimary: String
        var modelFallbacks: [String]
        var modelChoices: [String]
        var contextPruningMode: String
        var contextPruningTtl: String
        var compactionMode: String
        var heartbeatEvery: String
        var workspace: String
        var maxConcurrent: Int?
        var authProfiles: [ConfigAuthProfile]
    }
}
