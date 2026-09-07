import Foundation

nonisolated struct Manifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var datasetVersion: String
    var isSample: Bool
    var publishedAt: String
    var funds: [FundDescriptor]
}

nonisolated struct FundDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var currency: String
    var path: String
    var firstDate: String
    var lastDate: String
    var contentVersion: String? = nil
}

nonisolated struct FundSeries: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var datasetVersion: String
    var isSample: Bool
    var fundId: String
    var currency: String
    var valueBasis: String
    var source: DataSourceDescription
    var observations: [FundObservation]
}

nonisolated struct DataSourceDescription: Codable, Equatable, Sendable {
    var kind: String
    var name: String
    var url: String?
    var note: String
}

nonisolated struct FundObservation: Codable, Equatable, Sendable {
    var date: String
    var value: String
}

nonisolated struct DatasetSnapshot: Codable, Equatable, Sendable {
    var manifest: Manifest
    var series: [FundSeries]
}

nonisolated struct ValidatedFund: Sendable {
    let descriptor: FundDescriptor
    let series: FundSeries
    let values: [TradingDay: Decimal]
}

nonisolated struct ValidatedDataset: Sendable {
    let snapshot: DatasetSnapshot
    let funds: [ValidatedFund]
    let commonDates: [TradingDay]
    let earliestRequestedDate: TradingDay
    let endDate: TradingDay
}

nonisolated struct DataIssue: LocalizedError, Equatable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
