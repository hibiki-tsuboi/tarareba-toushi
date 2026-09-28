import CryptoKit
import Foundation

@testable import TararebaToushi

nonisolated enum Fixtures {
    // The catalog these fixtures deliver. The app itself no longer knows any product.
    static func ids(_ mode: DatasetMode = .sample) -> [String] {
        let ids = [
            "all-country", "sp500", "topix", "nasdaq100", "nikkei225", "gold", "emerging", "nanotech", "genomics",
            "developed-bond",
        ]
        return mode == .sample ? ids.map { "demo-\($0)" } : ids
    }

    // Final values per fund, in delivered order. Extra funds reuse the last value. Live data
    // uses fixed URLs, identified per fund by its contents; the sample uses versioned files.
    static func snapshot(
        version: String = "sample-v1", a: String = "12000", b: String = "14000", c: String = "13000",
        d: String = "16000", e: String = "15000", f: String = "17000", g: String = "18000",
        h: String = "19000", i: String = "20000", j: String = "21000", mode: DatasetMode = .sample
    ) -> DatasetSnapshot {
        let ids = ids(mode)
        let finals = [a, b, c, d, e, f, g, h, i, j]
        let names = [
            "オルカン", "S&P500", "TOPIX", "NASDAQ100", "日経平均", "純金", "新興国株", "ナノテク", "遺伝子工学",
            "先進国債券",
        ]
        let dates = ["2024-12-30", "2025-01-06", "2026-09-04"]
        let isSample = mode == .sample
        let series = ids.enumerated()
            .map { i, id in
                let observations = zip(dates, ["9900", "10000", finals[i]]).map { FundObservation(date: $0, value: $1) }
                return FundSeries(
                    schemaVersion: isSample ? 1 : 2,
                    datasetVersion: isSample ? version : contentVersion(id, observations), isSample: isSample,
                    fundId: id, currency: "JPY", valueBasis: isSample ? "reinvestedIndex" : "nav",
                    source: DataSourceDescription(
                        kind: isSample ? "synthetic" : "official", name: "テスト専用の架空値",
                        url: isSample ? nil : "https://example.com/fund", note: "実績ではありません"),
                    observations: observations)
            }
        let funds = ids.enumerated()
            .map { i, id in
                let name = names[i] + (isSample ? "（サンプル）" : "")
                return FundDescriptor(
                    id: id, displayName: name, shortName: name, summary: "テスト用の架空の商品",
                    currency: "JPY", valueBasis: series[i].valueBasis,
                    path: isSample ? "funds/\(id).\(version).json" : "funds/\(id).json",
                    firstDate: dates[0], lastDate: dates[2], contentVersion: isSample ? nil : series[i].datasetVersion)
            }
        let manifest = Manifest(
            schemaVersion: isSample ? 1 : 2, datasetVersion: version, isSample: isSample,
            publishedAt: "2026-09-06T00:00:00Z", funds: funds)
        return DatasetSnapshot(manifest: manifest, series: series)
    }

    // Changes whenever a fund's values do, as the published identifier does.
    private static func contentVersion(_ id: String, _ observations: [FundObservation]) -> String {
        let text = ([id] + observations.map { "\($0.date)=\($0.value)" }).joined(separator: "\n")
        return "fund-" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func validated(_ snapshot: DatasetSnapshot = snapshot()) throws -> ValidatedDataset {
        try DatasetValidator.validate(snapshot, mode: .sample)
    }

    // Assembled directly, so the domain can be exercised with histories of any shape.
    static func dataset(_ funds: [(id: String, dates: [String], values: [String])]) throws -> ValidatedDataset {
        let validated = try funds.map { fund in
            let descriptor = FundDescriptor(
                id: fund.id, displayName: fund.id, shortName: fund.id, summary: "テスト用の架空の商品",
                currency: "JPY", valueBasis: "nav", path: "funds/\(fund.id).json",
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

    // fund-a halves by February, doubles by March and ends 20% above its start; fund-b never moves.
    static func dipAndRecovery() throws -> ValidatedDataset {
        let dates = ["2025-01-06", "2025-01-20", "2025-02-06", "2025-03-06", "2025-03-10"]
        return try dataset([
            (id: "fund-a", dates: dates, values: ["10000", "11000", "5000", "20000", "12000"]),
            (id: "fund-b", dates: dates, values: ["10000", "10000", "10000", "10000", "10000"]),
        ])
    }

    // A full update is the catalog plus one history per delivered fund.
    static func requests(_ mode: DatasetMode = .sample) -> Int { ids(mode).count + 1 }

    static func envelope(_ snapshot: DatasetSnapshot = snapshot(), checkedAt: Date? = nil) -> StoredSnapshot {
        StoredSnapshot(
            identity: AppConfiguration(mode: snapshot.manifest.isSample ? .sample : .live).cacheIdentity,
            snapshot: snapshot, fetchedAt: Date(timeIntervalSince1970: 100), checkedAt: checkedAt)
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
