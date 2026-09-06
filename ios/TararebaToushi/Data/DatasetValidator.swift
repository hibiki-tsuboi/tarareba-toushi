import Foundation

nonisolated enum DatasetValidator {
    static func validateManifest(_ manifest: Manifest, mode: DatasetMode) throws {
        guard manifest.schemaVersion == AppConfiguration.schemaVersion else {
            throw DataIssue("未対応のデータ形式です。アプリの更新が必要な可能性があります。")
        }
        guard manifest.isSample == (mode == .sample) else { throw DataIssue("データのモードが一致しません。") }
        guard manifest.datasetVersion.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil,
            manifest.publishedAt.range(
                of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"#,
                options: .regularExpression) != nil,
            ISO8601DateFormatter().date(from: manifest.publishedAt) != nil,
            manifest.funds.count == 2,
            Set(manifest.funds.map(\.id)) == Set(mode.fundIDs)
        else {
            throw DataIssue("データ一覧の版・商品・公開日時が正しくありません。")
        }
        _ = try TradingDay(String(manifest.publishedAt.prefix(10)))
        for fund in manifest.funds {
            guard fund.currency == "JPY", !fund.displayName.isEmpty, fund.displayName.count <= 80,
                mode != .sample || fund.displayName.contains("サンプル"),
                fund.path == "funds/\(fund.id).\(manifest.datasetVersion).json"
            else {
                throw DataIssue("商品名・通貨・配信パスが正しくありません。")
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
        guard snapshot.series.count == 2, Set(snapshot.series.map(\.fundId)) == Set(mode.fundIDs) else {
            throw DataIssue("比較に必要な2商品の履歴が揃っていません。")
        }
        var funds: [ValidatedFund] = []
        var common: Set<TradingDay>?
        var firstDates: [TradingDay] = []
        for id in mode.fundIDs {
            guard let descriptor = snapshot.manifest.funds.first(where: { $0.id == id }),
                let series = snapshot.series.first(where: { $0.fundId == id }),
                series.schemaVersion == snapshot.manifest.schemaVersion,
                series.datasetVersion == snapshot.manifest.datasetVersion,
                series.isSample == snapshot.manifest.isSample, series.currency == descriptor.currency,
                ["reinvestedIndex", "navWithoutDistributions"].contains(series.valueBasis),
                !series.source.name.isEmpty, !series.source.note.isEmpty,
                mode != .sample || series.source.kind == "synthetic",
                !series.observations.isEmpty, series.observations.count <= 30_000,
                series.observations.first?.date == descriptor.firstDate,
                series.observations.last?.date == descriptor.lastDate
            else {
                throw DataIssue("データの版・系列の意味・期間が一致しません。")
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
            let dates = Set(values.keys)
            common = common.map { $0.intersection(dates) } ?? dates
            firstDates.append(try TradingDay(descriptor.firstDate))
            funds.append(ValidatedFund(descriptor: descriptor, series: series, values: values))
        }
        let dates = (common ?? []).sorted()
        guard let end = dates.last, let earliest = firstDates.max() else {
            throw DataIssue("両方のデータが揃う日がありません。")
        }
        return ValidatedDataset(
            snapshot: snapshot, funds: funds, commonDates: dates,
            earliestRequestedDate: earliest, endDate: end)
    }
}
