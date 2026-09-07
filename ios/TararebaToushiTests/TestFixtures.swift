import Foundation

@testable import TararebaToushi

nonisolated enum Fixtures {
    // Final values per fund, in delivered order. Extra funds reuse the last value.
    static func snapshot(
        version: String = "sample-v1", a: String = "12000", b: String = "14000", c: String = "13000",
        d: String = "16000", e: String = "15000", f: String = "17000", mode: DatasetMode = .sample
    ) -> DatasetSnapshot {
        let ids = mode.fundIDs
        let finals = [a, b, c, d, e, f]
        let names = ["オルカン", "S&P500", "TOPIX", "NASDAQ100", "日経平均", "純金"]
        let dates = ["2024-12-30", "2025-01-06", "2026-09-04"]
        let funds = ids.enumerated()
            .map { i, id in
                FundDescriptor(
                    id: id, displayName: names[i] + (mode == .sample ? "（サンプル）" : ""),
                    currency: "JPY", path: "funds/\(id).\(version).json", firstDate: dates[0], lastDate: dates[2])
            }
        let manifest = Manifest(
            schemaVersion: 1, datasetVersion: version, isSample: mode == .sample,
            publishedAt: "2026-09-06T00:00:00Z", funds: funds)
        let series = ids.enumerated()
            .map { i, id in
                FundSeries(
                    schemaVersion: 1, datasetVersion: version, isSample: mode == .sample, fundId: id, currency: "JPY",
                    valueBasis: mode == .sample ? "reinvestedIndex" : "nav",
                    source: DataSourceDescription(
                        kind: mode == .sample ? "synthetic" : "official", name: "テスト専用の架空値",
                        url: mode == .sample ? nil : "https://example.com/fund", note: "実績ではありません"),
                    observations: zip(dates, ["9900", "10000", finals[i]])
                        .map { FundObservation(date: $0, value: $1) })
            }
        return DatasetSnapshot(manifest: manifest, series: series)
    }

    static func validated(_ snapshot: DatasetSnapshot = snapshot()) throws -> ValidatedDataset {
        try DatasetValidator.validate(snapshot, mode: .sample)
    }

    // The validator still pins live data to the two delivered funds, so multi-fund
    // datasets are assembled directly to exercise the domain at N funds.
    static func dataset(_ funds: [(id: String, dates: [String], values: [String])]) throws -> ValidatedDataset {
        let validated = try funds.map { fund in
            let descriptor = FundDescriptor(
                id: fund.id, displayName: fund.id, currency: "JPY", path: "funds/\(fund.id).json",
                firstDate: fund.dates[0], lastDate: fund.dates[fund.dates.count - 1])
            let series = FundSeries(
                schemaVersion: 2, datasetVersion: "fund-test", isSample: false, fundId: fund.id,
                currency: "JPY", valueBasis: "nav",
                source: DataSourceDescription(
                    kind: "official", name: "テスト専用の架空値", url: "https://example.com/fund",
                    note: "実績ではありません"),
                observations: zip(fund.dates, fund.values).map { FundObservation(date: $0, value: $1) })
            var values: [TradingDay: Decimal] = [:]
            for observation in series.observations {
                values[try TradingDay(observation.date)] = try DatasetValidator.decimal(observation.value)
            }
            return ValidatedFund(descriptor: descriptor, series: series, values: values)
        }
        let manifest = Manifest(
            schemaVersion: 2, datasetVersion: "multi", isSample: false,
            publishedAt: "2026-09-06T00:00:00Z", funds: validated.map(\.descriptor))
        guard let latest = try validated.map({ try TradingDay($0.descriptor.lastDate) }).max() else {
            throw DataIssue("商品がありません。")
        }
        return ValidatedDataset(
            snapshot: DatasetSnapshot(manifest: manifest, series: validated.map(\.series)),
            funds: validated, latestDate: latest)
    }

    // A full update is the catalog plus one history per delivered fund.
    static func requests(_ mode: DatasetMode = .sample) -> Int { mode.fundIDs.count + 1 }

    static func envelope(_ snapshot: DatasetSnapshot = snapshot(), checkedAt: Date? = nil) -> StoredSnapshot {
        StoredSnapshot(
            identity: AppConfiguration(mode: snapshot.manifest.isSample ? .sample : .live).cacheIdentity,
            snapshot: snapshot, origin: .remote,
            fetchedAt: Date(timeIntervalSince1970: 100), checkedAt: checkedAt)
    }

    static func responses(_ snapshot: DatasetSnapshot) throws -> [String: Data] {
        let mode = snapshot.manifest.isSample ? "sample" : "live"
        var values = ["/\(mode)/manifest.json": try JSONEncoder().encode(snapshot.manifest)]
        for f in snapshot.manifest.funds {
            values["/\(mode)/\(f.path)"] = try JSONEncoder().encode(snapshot.series.first { $0.fundId == f.id })
        }
        return values
    }
}

actor MockTransport: JSONTransport {
    var responses: [String: Data]
    var requests: [URL] = []
    let delay: UInt64
    init(_ responses: [String: Data] = [:], delay: UInt64 = 0) {
        self.responses = responses
        self.delay = delay
    }
    func fetch(_ url: URL) async throws -> Data {
        requests.append(url)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        guard let data = responses[url.path] else { throw DataIssue("配信ファイルがまだ配置されていません（404）。") }
        return data
    }
    func set(_ responses: [String: Data]) { self.responses = responses }
    var count: Int { requests.count }
}

actor MemoryStore: SnapshotStore {
    var value: StoredSnapshot?
    let corrupt: Bool
    let failSave: Bool
    init(_ value: StoredSnapshot? = nil, corrupt: Bool = false, failSave: Bool = false) {
        self.value = value
        self.corrupt = corrupt
        self.failSave = failSave
    }
    func load() throws -> StoredSnapshot? {
        if corrupt { throw DataIssue("破損キャッシュ") }
        return value
    }
    func save(_ value: StoredSnapshot) throws {
        if failSave { throw DataIssue("保存失敗") }
        self.value = value
    }
}
