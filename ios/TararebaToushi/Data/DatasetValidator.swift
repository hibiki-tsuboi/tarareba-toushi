import Foundation
import CryptoKit

nonisolated enum DatasetValidator {
    static func validateManifest(_ manifest: Manifest, mode: DatasetMode) throws {
        guard [1, AppConfiguration.schemaVersion].contains(manifest.schemaVersion),
            mode == .live || manifest.schemaVersion == 1
        else {
            throw DataIssue("未対応のデータ形式です。アプリの更新が必要な可能性があります。")
        }
        guard manifest.isSample == (mode == .sample) else { throw DataIssue("データのモードが一致しません。") }
        guard manifest.datasetVersion.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil,
            manifest.publishedAt.range(
                of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"#,
                options: .regularExpression) != nil,
            ISO8601DateFormatter().date(from: manifest.publishedAt) != nil,
            !manifest.funds.isEmpty, manifest.funds.count <= 1000,
            Set(manifest.funds.map(\.id)).count == manifest.funds.count,
            Set(mode.fundIDs).isSubset(of: Set(manifest.funds.map(\.id))),
            manifest.schemaVersion == 2 || manifest.funds.count == mode.fundIDs.count
        else {
            throw DataIssue("データ一覧の版・商品・公開日時が正しくありません。")
        }
        _ = try TradingDay(String(manifest.publishedAt.prefix(10)))
        for fund in manifest.funds {
            guard fund.currency == "JPY", !fund.displayName.isEmpty, fund.displayName.count <= 80,
                fund.displayName.contains("サンプル") == (mode == .sample),
                fund.id.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil
            else {
                throw DataIssue("商品名・通貨・配信パスが正しくありません。")
            }
            if manifest.schemaVersion == 2 {
                guard fund.path == "funds/\(fund.id).json",
                    fund.contentVersion?.range(of: #"^fund-[a-f0-9]{64}$"#, options: .regularExpression) != nil
                else { throw DataIssue("商品の配信パス・更新情報が正しくありません。") }
            } else if fund.path != "funds/\(fund.id).\(manifest.datasetVersion).json" {
                throw DataIssue("商品の配信パスが正しくありません。")
            }
            guard try TradingDay(fund.firstDate) <= TradingDay(fund.lastDate) else {
                throw DataIssue("履歴の開始日と終了日が逆転しています。")
            }
        }
    }

    static func decimal(_ text: String) throws -> Decimal {
        // At most 12 integer digits and 6 fractional digits. No exponents or partial parses.
        guard text.range(of: #"^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$"#, options: .regularExpression) != nil,
            let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
            !value.isNaN, value > 0
        else {
            throw DataIssue("系列値は正の10進数で指定してください。")
        }
        return value
    }

    static func validate(_ snapshot: DatasetSnapshot, mode: DatasetMode) throws -> ValidatedDataset {
        try validateManifest(snapshot.manifest, mode: mode)
        guard snapshot.series.count == mode.fundIDs.count,
            Set(snapshot.series.map(\.fundId)) == Set(mode.fundIDs)
        else {
            throw DataIssue("比較に必要な商品の履歴が揃っていません。")
        }
        var funds: [ValidatedFund] = []
        var latest: TradingDay?
        for id in mode.fundIDs {
            guard let descriptor = snapshot.manifest.funds.first(where: { $0.id == id }),
                let series = snapshot.series.first(where: { $0.fundId == id }),
                series.schemaVersion == snapshot.manifest.schemaVersion,
                series.datasetVersion == (snapshot.manifest.schemaVersion == 2
                    ? descriptor.contentVersion : snapshot.manifest.datasetVersion),
                series.isSample == snapshot.manifest.isSample, series.currency == descriptor.currency,
                supportsValueBasis(series, mode: mode),
                !series.source.name.isEmpty, !series.source.note.isEmpty,
                series.source.kind == (mode == .sample ? "synthetic" : "official"),
                !series.observations.isEmpty, series.observations.count <= 30_000,
                series.observations.first?.date == descriptor.firstDate,
                series.observations.last?.date == descriptor.lastDate
            else {
                throw DataIssue("データの版・系列の意味・期間が一致しません。")
            }
            if mode == .live {
                guard let text = series.source.url, let url = URL(string: text),
                    url.scheme == "https", url.host != nil, url.user == nil, url.password == nil
                else { throw DataIssue("実データの出典URLが正しくありません。") }
            }
            var previous: TradingDay?
            var values: [TradingDay: Decimal] = [:]
            for observation in series.observations {
                let day = try TradingDay(observation.date)
                guard previous == nil || previous.map({ $0 < day }) == true else {
                    throw DataIssue("観測日は重複のない昇順で指定してください。")
                }
                values[day] = try decimal(observation.value)
                previous = day
            }
            let lastDate = try TradingDay(descriptor.lastDate)
            latest = latest.map { Swift.max($0, lastDate) } ?? lastDate
            var displaySeries = series
            if mode == .live, series.valueBasis == "reinvestedIndex" {
                // This exact legacy edition was verified to contain ordinary NAVs.
                // Keep the original snapshot intact for cache and version comparisons.
                displaySeries.valueBasis = "nav"
                displaySeries.source.note = "通常の基準価額（1万口あたり・信託報酬控除後）を使用。分配金の受取額・再投資は含みません。"
            }
            funds.append(ValidatedFund(descriptor: descriptor, series: displaySeries, values: values))
        }
        guard let latest else { throw DataIssue("比較できる商品がありません。") }
        let dataset = ValidatedDataset(snapshot: snapshot, funds: funds, latestDate: latest)
        // Reject data that cannot produce the comparison shown on first launch.
        _ = try dataset.window(for: dataset.defaultSelection)
        return dataset
    }

    private static func supportsValueBasis(_ series: FundSeries, mode: DatasetMode) -> Bool {
        if ["nav", "navWithoutDistributions"].contains(series.valueBasis) { return true }
        guard series.valueBasis == "reinvestedIndex" else { return false }
        if mode == .sample { return true }
        // Allow only the published/cached edition audited on 2026-09-07. Other
        // reinvested series cannot be used as ordinary NAVs, even with this version label.
        guard series.datasetVersion == "mufg-20260904-6c4cf880560d" else { return false }
        let hashes = [
            "all-country": "20277ded02e488fb01ad2aa873e46a8eca1d53764d6f69e371237e243ef91118",
            "sp500": "a051e6051d70650bf3988b034beb322ddba4b0a199621b809d6e5e5b5c9d6f3b",
        ]
        let text = series.observations.map { "\($0.date):\($0.value)\n" }.joined()
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return hash == hashes[series.fundId]
    }
}
