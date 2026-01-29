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
    var authCheckStatus: String?
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
    var authProfilesPath: String?
    var authProfilesText = ""
    var authProfilesOriginalText = ""
    var isLoadingAuthProfiles = false
    var authProfilesError: String?
    var authProfilesDraft: AuthProfilesDraft?
    var authProfilesDraftError: String?
    var authProfilesDraftOriginal: AuthProfilesDraft?
    private var authProfilesDocument: [String: Any] = [:]
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

    func verifyAuthProfiles() async {
        authCheckStatus = "Testing connection…"
        do {
            await ensureConnected()
            let runId = try await gateway.chatSend(
                message: "ping",
                sessionKey: "auth-check",
                thinking: "off"
            )
            _ = try? await gateway.chatAbort(sessionKey: "auth-check", runId: runId)
            authCheckStatus = "Connection ok"
        } catch {
            authCheckStatus = "Connection failed: \(error.localizedDescription)"
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
        await loadAuthProfilesFile()
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

    func loadAuthProfilesFile() async {
        isLoadingAuthProfiles = true
        authProfilesError = nil
        defer { isLoadingAuthProfiles = false }

        let url = ClawdbotPaths.authProfilesURL
        authProfilesPath = url.path
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let formatted = Self.prettyPrintedJson(from: text) ?? text
                authProfilesText = formatted
                authProfilesOriginalText = formatted
                if let document = Self.jsonDocument(from: formatted) {
                    authProfilesDocument = document
                    let draft = Self.buildAuthProfilesDraft(from: document)
                    authProfilesDraft = draft
                    authProfilesDraftOriginal = draft
                    authProfilesDraftError = nil
                } else {
                    authProfilesDraft = nil
                    authProfilesDraftOriginal = nil
                    authProfilesDraftError = "Auth profiles JSON is invalid."
                }
            } catch {
                authProfilesError = "Unable to load auth profiles: \(error.localizedDescription)"
                authProfilesText = ""
                authProfilesOriginalText = ""
                authProfilesDraft = nil
                authProfilesDraftOriginal = nil
                authProfilesDraftError = nil
            }
        } else {
            authProfilesError = "File not found. Save to create it."
            authProfilesText = ""
            authProfilesOriginalText = ""
            authProfilesDraft = AuthProfilesDraft(profiles: [])
            authProfilesDraftOriginal = authProfilesDraft
        }
    }

    func saveAuthProfilesFile() async {
        let url = ClawdbotPaths.authProfilesURL
        authProfilesPath = url.path
        if let draft = authProfilesDraft {
            var document = authProfilesDocument
            Self.applyAuthProfilesDraft(draft, to: &document)
            authProfilesDocument = document
            if let formatted = Self.prettyPrintedJson(from: document) {
                authProfilesText = formatted
            }
        }
        guard let formatted = Self.prettyPrintedJson(from: authProfilesText) else {
            authProfilesError = "Auth profiles JSON is invalid."
            return
        }
        authProfilesText = formatted
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try authProfilesText.write(to: url, atomically: true, encoding: .utf8)
            authProfilesOriginalText = authProfilesText
            authProfilesDraftOriginal = authProfilesDraft
            authProfilesError = nil
            await gateway.disconnect()
            await gateway.connect()
            await refreshModelStatus()
        } catch {
            authProfilesError = "Unable to save auth profiles: \(error.localizedDescription)"
        }
    }

    func revertAuthProfilesEdits() {
        authProfilesText = authProfilesOriginalText
        authProfilesError = nil
        if let document = Self.jsonDocument(from: authProfilesOriginalText) {
            authProfilesDocument = document
            let draft = Self.buildAuthProfilesDraft(from: document)
            authProfilesDraft = draft
            authProfilesDraftOriginal = draft
            authProfilesDraftError = nil
        }
    }

    func updateAuthProfilesDraft(_ mutate: (inout AuthProfilesDraft) -> Void) {
        guard var draft = authProfilesDraft else { return }
        mutate(&draft)
        if draft == authProfilesDraft {
            return
        }
        authProfilesDraft = draft
        syncAuthProfilesTextFromDraft(draft)
    }

    func clearAuthProfileUsage(profileId: String) {
        var document = authProfilesDocument
        if var usage = document["usageStats"] as? [String: Any] {
            usage.removeValue(forKey: profileId)
            document["usageStats"] = usage
        }
        authProfilesDocument = document
        if let formatted = Self.prettyPrintedJson(from: document) {
            authProfilesText = formatted
        }
        let draft = Self.buildAuthProfilesDraft(from: document)
        authProfilesDraft = draft
        authProfilesDraftOriginal = authProfilesDraftOriginal ?? draft
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

    private func syncAuthProfilesTextFromDraft(_ draft: AuthProfilesDraft) {
        var document = authProfilesDocument
        Self.applyAuthProfilesDraft(draft, to: &document)
        authProfilesDocument = document
        if let formatted = Self.prettyPrintedJson(from: document) {
            authProfilesText = formatted
        }
    }

    nonisolated static func buildAuthProfilesDraft(from document: [String: Any]) -> AuthProfilesDraft {
        let profiles = (document["profiles"] as? [String: Any]) ?? [:]
        let usage = (document["usageStats"] as? [String: Any]) ?? [:]
        let drafts: [AuthProfileDraft] = profiles.compactMap { key, value in
            guard let dict = value as? [String: Any] else { return nil }
            let type = dict["type"] as? String ?? ""
            let provider = dict["provider"] as? String ?? ""
            let email = dict["email"] as? String ?? ""
            let keyValue = dict["key"] as? String ?? ""
            let token = dict["token"] as? String ?? ""
            let access = dict["access"] as? String ?? ""
            let refresh = dict["refresh"] as? String ?? ""
            let expires = dict["expires"] as? Int ?? (dict["expires"] as? NSNumber).map { $0.intValue }

            let knownKeys: Set<String> = [
                "type", "provider", "email", "key", "token", "access", "refresh", "expires"
            ]
            let extras = dict.compactMap { entry -> AuthProfileExtraField? in
                if knownKeys.contains(entry.key) { return nil }
                let value: String
                if let string = entry.value as? String {
                    value = string
                } else if let number = entry.value as? NSNumber {
                    value = number.stringValue
                } else if let bool = entry.value as? Bool {
                    value = bool ? "true" : "false"
                } else {
                    return nil
                }
                return AuthProfileExtraField(key: entry.key, value: value)
            }.sorted {
                $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }

            let usageEntry = usage[key] as? [String: Any]
            let cooldownUntil = usageEntry?["cooldownUntil"] as? Int
                ?? (usageEntry?["cooldownUntil"] as? NSNumber).map { $0.intValue }
            let disabledUntil = usageEntry?["disabledUntil"] as? Int
                ?? (usageEntry?["disabledUntil"] as? NSNumber).map { $0.intValue }
            let disabledReason = usageEntry?["disabledReason"] as? String
            let errorCount = usageEntry?["errorCount"] as? Int
                ?? (usageEntry?["errorCount"] as? NSNumber).map { $0.intValue }
            let lastFailureAt = usageEntry?["lastFailureAt"] as? Int
                ?? (usageEntry?["lastFailureAt"] as? NSNumber).map { $0.intValue }

            return AuthProfileDraft(
                id: key,
                type: type,
                provider: provider,
                email: email,
                apiKey: keyValue,
                token: token,
                access: access,
                refresh: refresh,
                expires: expires,
                cooldownUntil: cooldownUntil,
                disabledUntil: disabledUntil,
                disabledReason: disabledReason,
                errorCount: errorCount,
                lastFailureAt: lastFailureAt,
                extraFields: extras
            )
        }
        .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }

        return AuthProfilesDraft(profiles: drafts)
    }

    nonisolated static func applyAuthProfilesDraft(_ draft: AuthProfilesDraft, to document: inout [String: Any]) {
        var profiles: [String: Any] = [:]
        for profile in draft.profiles {
            let id = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty { continue }

            var dict: [String: Any] = [:]
            if !profile.type.isEmpty { dict["type"] = profile.type }
            if !profile.provider.isEmpty { dict["provider"] = profile.provider }
            if !profile.email.isEmpty { dict["email"] = profile.email }

            switch profile.type {
            case "api_key":
                if !profile.apiKey.isEmpty { dict["key"] = profile.apiKey }
            case "token":
                if !profile.token.isEmpty { dict["token"] = profile.token }
            case "oauth":
                if !profile.access.isEmpty { dict["access"] = profile.access }
                if !profile.refresh.isEmpty { dict["refresh"] = profile.refresh }
            default:
                break
            }

            if let expires = profile.expires { dict["expires"] = expires }

            for extra in profile.extraFields where !extra.key.isEmpty {
                dict[extra.key] = extra.value
            }

            profiles[id] = dict
        }
        document["profiles"] = profiles
        if document["version"] == nil {
            document["version"] = 1
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

    struct AuthProfileExtraField: Identifiable, Hashable {
        let id = UUID()
        var key: String
        var value: String
    }

    struct AuthProfileDraft: Identifiable, Hashable {
        var id: String
        var type: String
        var provider: String
        var email: String
        var apiKey: String
        var token: String
        var access: String
        var refresh: String
        var expires: Int?
        var cooldownUntil: Int?
        var disabledUntil: Int?
        var disabledReason: String?
        var errorCount: Int?
        var lastFailureAt: Int?
        var extraFields: [AuthProfileExtraField]
    }

    struct AuthProfilesDraft: Hashable {
        var profiles: [AuthProfileDraft]
    }
}
