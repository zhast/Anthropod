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

    var usageSummary: GatewayCostUsageSummary?
    var isLoadingUsage = false
    var usageError: String?

    var compactStatus: String?

    func refreshAll() async {
        await ensureConnected()
        await refreshModels()
        await refreshUsage()
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
