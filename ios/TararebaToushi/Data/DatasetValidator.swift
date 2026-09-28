import Foundation

nonisolated enum DatasetValidator {
    private static let idPattern = #"^[a-z0-9][a-z0-9-]{0,63}$"#

    // The products this version can compare, in delivered order and within its limit.
    // Anything else in the catalog is left out rather than rejected: a later catalog may
    // list kinds of product only a later version understands, and this one must keep
    // working beside them. Only a catalog that is unusable as a whole is rejected.
    @discardableResult
    static func validateManifest(_ manifest: Manifest, mode: DatasetMode) throws -> [FundDescriptor] {
        // Live data is the fixed-URL format; the sample keeps its versioned files.
        guard manifest.schemaVersion == (mode == .sample ? 1 : AppConfiguration.schemaVersion) else {
            throw DataIssue("未対応のデータ形式です。アプリの更新が必要な可能性があります。")
        }
        guard manifest.isSample == (mode == .sample) else { throw DataIssue("データのモードが一致しません。") }
        guard manifest.datasetVersion.range(of: idPattern, options: .regularExpression) != nil,
            manifest.publishedAt.range(
                of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"#,
                options: .regularExpression) != nil,
            ISO8601DateFormatter().date(from: manifest.publishedAt) != nil,
            manifest.funds.count <= 1000,
            Set(manifest.funds.map(\.id)).count == manifest.funds.count
        else {
            throw DataIssue("データ一覧の版・商品・公開日時が正しくありません。")
        }
        _ = try TradingDay(String(manifest.publishedAt.prefix(10)))
        let usable = manifest.funds.filter { isUsable($0, in: manifest, mode: mode) }
        guard !usable.isEmpty else {
            throw DataIssue("このバージョンで比較できる商品がありません。アプリの更新が必要な可能性があります。")
        }
        return Array(usable.prefix(AppConfiguration.maximumCatalogFunds))
    }

    private static func isUsable(_ fund: FundDescriptor, in manifest: Manifest, mode: DatasetMode) -> Bool {
        let isSample = mode == .sample
        guard fund.currency == "JPY", fund.valueBasis == valueBasis(for: mode),
            fund.id.range(of: idPattern, options: .regularExpression) != nil,
            isText(fund.displayName, upTo: 80), isText(fund.shortName, upTo: 20), isText(fund.summary, upTo: 60),
            fund.category.map({ isText($0, upTo: 20) }) ?? true,
            // A sample must never pass for real data, nor real data for a sample.
            fund.displayName.contains("サンプル") == isSample, fund.shortName.contains("サンプル") == isSample,
            let first = try? TradingDay(fund.firstDate), let last = try? TradingDay(fund.lastDate), first <= last
        else { return false }
        if manifest.schemaVersion == 2 {
            return fund.path == "funds/\(fund.id).json"
                && fund.contentVersion?.range(of: #"^fund-[a-f0-9]{64}$"#, options: .regularExpression) != nil
        }
        return fund.path == "funds/\(fund.id).\(manifest.datasetVersion).json"
    }

    // The one kind of value each mode computes: an ordinary NAV, or the sample's synthetic index.
    private static func valueBasis(for mode: DatasetMode) -> String {
        mode == .sample ? "reinvestedIndex" : "nav"
    }

    private static func isText(_ text: String, upTo limit: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= limit
    }

    static func isNotice(_ text: String) -> Bool { isText(text, upTo: 200) }

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
        let usable = try validateManifest(snapshot.manifest, mode: mode)
        guard snapshot.series.count == usable.count,
            Set(snapshot.series.map(\.fundId)) == Set(usable.map(\.id))
        else {
            throw DataIssue("比較に必要な商品の履歴が揃っていません。")
        }
        var funds: [ValidatedFund] = []
        var latest: TradingDay?
        for descriptor in usable {
            guard let series = snapshot.series.first(where: { $0.fundId == descriptor.id }),
                series.schemaVersion == snapshot.manifest.schemaVersion,
                series.datasetVersion == (snapshot.manifest.schemaVersion == 2
                    ? descriptor.contentVersion : snapshot.manifest.datasetVersion),
                series.isSample == snapshot.manifest.isSample, series.currency == descriptor.currency,
                series.valueBasis == descriptor.valueBasis,
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
            funds.append(ValidatedFund(descriptor: descriptor, series: series, values: values))
        }
        guard let latest else { throw DataIssue("比較できる商品がありません。") }
        let dataset = ValidatedDataset(snapshot: snapshot, funds: funds, latestDate: latest)
        // Reject data that cannot produce the comparison shown on first launch.
        _ = try dataset.window(for: dataset.defaultSelection)
        return dataset
    }
}
