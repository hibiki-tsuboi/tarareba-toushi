import Foundation

nonisolated struct SimulationInput: Codable, Sendable {
    var amount: Int
    var requestedDate: String
}

nonisolated struct ValuationPoint: Identifiable, Sendable {
    var id: String { day.rawValue }
    let day: TradingDay
    let amount: Decimal
}

nonisolated struct FundResult: Identifiable, Sendable {
    var id: String { descriptor.id }
    let descriptor: FundDescriptor
    let points: [ValuationPoint]
    let valuation: Decimal
    let profit: Decimal
    let returnPercent: Decimal
    let displayedValuation: Decimal
    let displayedProfit: Decimal
}

nonisolated struct SimulationResult: Sendable {
    let isSample: Bool
    let input: SimulationInput
    let requestedDate: TradingDay
    let startDate: TradingDay
    let endDate: TradingDay
    let funds: [FundResult]
    let displayedDifference: Decimal
}

nonisolated enum ComparisonDateResolver {
    static func dates(for requested: TradingDay, in dataset: ValidatedDataset) throws -> [TradingDay] {
        guard requested >= dataset.earliestRequestedDate, requested <= dataset.endDate else {
            throw DataIssue("この期間のデータがありません。\(dataset.earliestRequestedDate.label)〜\(dataset.endDate.label)から選んでください。")
        }
        let dates = dataset.commonDates.filter { $0 >= requested }
        guard !dates.isEmpty else { throw DataIssue("比較できる共通日がありません。") }
        return dates
    }
}

nonisolated enum SimulationCalculator {
    static func calculate(_ input: SimulationInput, dataset: ValidatedDataset) throws -> SimulationResult {
        guard (1...AppConfiguration.maximumAmount).contains(input.amount) else {
            throw DataIssue("投資金額は1円〜10億円で入力してください。")
        }
        let requested = try TradingDay(input.requestedDate)
        let dates = try ComparisonDateResolver.dates(for: requested, in: dataset)
        guard let start = dates.first, let end = dates.last else { throw DataIssue("比較期間がありません。") }
        let principal = Decimal(input.amount)
        let results = try dataset.funds.map { fund in
            guard let initial = fund.values[start], initial > 0 else { throw DataIssue("開始日の値が不正です。") }
            let points = try dates.map { day in
                guard let value = fund.values[day], value > 0 else { throw DataIssue("比較日の値が不正です。") }
                return ValuationPoint(day: day, amount: principal * value / initial)
            }
            guard let last = points.last, let endValue = fund.values[end], !last.amount.isNaN else {
                throw DataIssue("評価額を計算できませんでした。")
            }
            let rounded = MoneyFormat.round(last.amount)
            return FundResult(
                descriptor: fund.descriptor, points: points, valuation: last.amount,
                profit: last.amount - principal, returnPercent: (endValue / initial - 1) * 100,
                displayedValuation: rounded, displayedProfit: rounded - principal)
        }
        guard results.count == 2 else { throw DataIssue("2商品の比較が必要です。") }
        return SimulationResult(
            isSample: dataset.snapshot.manifest.isSample,
            input: input, requestedDate: requested, startDate: start, endDate: end,
            funds: results, displayedDifference: results[1].displayedValuation - results[0].displayedValuation)
    }
}

nonisolated enum MoneyFormat {
    static func round(_ value: Decimal, scale: Int = 0) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    static func number(_ value: Decimal, digits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: round(value, scale: digits))) ?? "—"
    }

    static func yen(_ value: Decimal) -> String { number(value) + "円" }
    static func signed(_ value: Decimal, digits: Int = 0) -> String {
        let rounded = round(value, scale: digits)
        return (rounded > 0 ? "＋" : rounded < 0 ? "−" : "") + number(abs(rounded), digits: digits)
    }

    static func parseAmount(_ text: String) throws -> Int {
        let normalized = text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: ",", with: "")
        guard normalized.range(of: #"^[0-9]{1,10}$"#, options: .regularExpression) != nil,
            let amount = Int(normalized), (1...AppConfiguration.maximumAmount).contains(amount)
        else {
            throw DataIssue("投資金額は1円〜10億円の整数で入力してください。")
        }
        return amount
    }
}
