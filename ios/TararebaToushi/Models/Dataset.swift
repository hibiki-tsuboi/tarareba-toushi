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

// The comparable period depends on which funds are selected: a fund with a short
// history must not shorten the period of the funds it is not being compared with.
nonisolated struct ComparisonWindow: Sendable {
    let dates: [TradingDay]
    let earliestRequestedDate: TradingDay
    let endDate: TradingDay
}

nonisolated struct ValidatedDataset: Sendable {
    let snapshot: DatasetSnapshot
    let funds: [ValidatedFund]
    let latestDate: TradingDay

    var defaultSelection: [String] {
        funds.prefix(AppConfiguration.defaultComparisonFunds).map(\.descriptor.id)
    }

    // Results keep the delivered order rather than the tapping order.
    func funds(for ids: [String]) throws -> [ValidatedFund] {
        let requested = Set(ids)
        let selected = funds.filter { requested.contains($0.descriptor.id) }
        guard !selected.isEmpty, selected.count == requested.count else {
            throw DataIssue("選択した商品のデータが見つかりません。")
        }
        guard selected.count <= AppConfiguration.maximumComparisonFunds else {
            throw DataIssue("比較できるのは\(AppConfiguration.maximumComparisonFunds)商品までです。")
        }
        return selected
    }

    func window(for selected: [ValidatedFund]) throws -> ComparisonWindow {
        var common: Set<TradingDay>?
        var earliest: TradingDay?
        for fund in selected {
            let dates = Set(fund.values.keys)
            common = common.map { $0.intersection(dates) } ?? dates
            let first = try TradingDay(fund.descriptor.firstDate)
            earliest = earliest.map { Swift.max($0, first) } ?? first
        }
        let dates = (common ?? []).sorted()
        guard let end = dates.last, let earliest else {
            throw DataIssue("選択した商品に共通する観測日がありません。")
        }
        return ComparisonWindow(dates: dates, earliestRequestedDate: earliest, endDate: end)
    }

    func window(for ids: [String]) throws -> ComparisonWindow {
        try window(for: try funds(for: ids))
    }

    // The same bounds window(for:) enforces, without intersecting whole histories: the input
    // screen asks again on every change. The last common day has to be one of the days of
    // the history that ends first, so walking that one back finds it.
    func startRange(for ids: [String]) throws -> ClosedRange<TradingDay> {
        let selected = try funds(for: ids)
        let earliest = try selected.map { try TradingDay($0.descriptor.firstDate) }.max()
        guard let earliest, let endsFirst = selected.min(by: { $0.descriptor.lastDate < $1.descriptor.lastDate })
        else { throw DataIssue("選択した商品に共通する観測日がありません。") }
        for observation in endsFirst.series.observations.reversed() {
            let day = try TradingDay(observation.date)
            guard day >= earliest else { break }
            if selected.allSatisfy({ $0.values[day] != nil }) { return earliest...day }
        }
        throw DataIssue("選択した商品に共通する観測日がありません。")
    }
}

nonisolated struct DataIssue: LocalizedError, Equatable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
