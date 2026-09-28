import Foundation

// The catalog decides which products exist; the app only knows which kinds it can compute.
nonisolated struct Manifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var datasetVersion: String
    var isSample: Bool
    var publishedAt: String
    var funds: [FundDescriptor]
    // Wording a provider asks for, such as a trademark, that the app cannot know in advance.
    var notices: [String] = []
}

extension Manifest {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        datasetVersion = try container.decode(String.self, forKey: .datasetVersion)
        isSample = try container.decode(Bool.self, forKey: .isSample)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        // A later catalog may describe a product in a way this version cannot read. That
        // product is left out; the catalog stays usable for the products it can read.
        funds = try container.decode([Lossy<FundDescriptor>].self, forKey: .funds).compactMap(\.value)
        notices = try container.decodeIfPresent([Lossy<String>].self, forKey: .notices)?.compactMap(\.value) ?? []
    }
}

nonisolated private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}

nonisolated struct FundDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: String
    // The official name, shown with the source.
    var displayName: String
    // What the screens call it.
    var shortName: String
    // What it holds, in words that need no index name.
    var summary: String
    // Groups the picker's list; products without one are listed together.
    var category: String? = nil
    var currency: String
    // What a value means. Only the kinds this version can compute are offered.
    var valueBasis: String
    var path: String
    var firstDate: String
    var lastDate: String
    var contentVersion: String? = nil
}

nonisolated struct FundGroup: Identifiable, Sendable {
    var id: String { title ?? "" }
    let title: String?
    let funds: [FundDescriptor]

    // Groups in the order they first appear. A catalog without categories stays one
    // untitled list; products without one gather under その他 once others have one.
    static func grouping(_ funds: [FundDescriptor]) -> [FundGroup] {
        guard funds.contains(where: { $0.category != nil }) else { return [FundGroup(title: nil, funds: funds)] }
        var titles: [String] = []
        var members: [String: [FundDescriptor]] = [:]
        for fund in funds {
            let title = fund.category ?? "その他"
            if members[title] == nil { titles.append(title) }
            members[title, default: []].append(fund)
        }
        return titles.map { FundGroup(title: $0, funds: members[$0] ?? []) }
    }
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

    // Delivered products this version leaves out, because it cannot compute them or
    // offers no more than its limit. Updating the app may make them available.
    var hiddenFundCount: Int { snapshot.manifest.funds.count - funds.count }

    var notices: [String] {
        snapshot.manifest.notices.filter(DatasetValidator.isNotice).prefix(AppConfiguration.maximumNotices).map { $0 }
    }

    var sourceNames: [String] { Self.sourceNames(of: funds) }

    // Each provider once, in delivered order.
    static func sourceNames(of funds: [ValidatedFund]) -> [String] {
        var names: [String] = []
        for fund in funds where !names.contains(fund.series.source.name) { names.append(fund.series.source.name) }
        return names
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
