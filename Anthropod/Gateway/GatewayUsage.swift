//
//  GatewayUsage.swift
//  Anthropod
//
//  Usage cost payloads for gateway usage.cost
//

import Foundation

@preconcurrency
struct GatewayCostUsageTotals: Codable, Sendable {
    nonisolated let input: Int
    nonisolated let output: Int
    nonisolated let cacheRead: Int
    nonisolated let cacheWrite: Int
    nonisolated let totalTokens: Int
    nonisolated let totalCost: Double
    nonisolated let missingCostEntries: Int
}

@preconcurrency
struct GatewayCostUsageDay: Codable, Sendable {
    nonisolated let date: String
    nonisolated let input: Int
    nonisolated let output: Int
    nonisolated let cacheRead: Int
    nonisolated let cacheWrite: Int
    nonisolated let totalTokens: Int
    nonisolated let totalCost: Double
    nonisolated let missingCostEntries: Int
}

@preconcurrency
struct GatewayCostUsageSummary: Codable, Sendable {
    nonisolated let updatedAt: Double
    nonisolated let days: Int
    nonisolated let daily: [GatewayCostUsageDay]
    nonisolated let totals: GatewayCostUsageTotals
}

enum CostUsageFormatting {
    static func formatUsd(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        if value >= 1 { return String(format: "$%.2f", value) }
        if value >= 0.01 { return String(format: "$%.2f", value) }
        return String(format: "$%.4f", value)
    }

    static func formatTokenCount(_ value: Int?) -> String? {
        guard let value else { return nil }
        let safe = max(0, value)
        if safe >= 1_000_000 { return String(format: "%.1fm", Double(safe) / 1_000_000.0) }
        if safe >= 1000 {
            return safe >= 10000
                ? String(format: "%.0fk", Double(safe) / 1000.0)
                : String(format: "%.1fk", Double(safe) / 1000.0)
        }
        return String(safe)
    }
}
