import Foundation

nonisolated struct SimulationInput: Codable, Sendable {
    var amount: Int
    var requestedDate: String
    // Absent in snapshots saved before selection existed; nil means the default pair.
    var fundIDs: [String]? = nil
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

    var shortName: String { descriptor.shortName }
}

nonisolated struct SimulationResult: Sendable {
    let isSample: Bool
    let input: SimulationInput
    let requestedDate: TradingDay
    let startDate: TradingDay
    let endDate: TradingDay
    let funds: [FundResult]
    // Signed, and only meaningful for exactly two funds: funds[1] - funds[0].
    let displayedDifference: Decimal

    var ranking: [FundResult] {
        funds.sorted { $0.displayedValuation > $1.displayedValuation }
    }

    var displayedSpread: Decimal {
        let values = funds.map(\.displayedValuation)
        guard let high = values.max(), let low = values.min() else { return 0 }
        return high - low
    }
}

nonisolated enum ComparisonDateResolver {
    static func dates(for requested: TradingDay, in window: ComparisonWindow) throws -> [TradingDay] {
        guard requested >= window.earliestRequestedDate, requested <= window.endDate else {
            throw DataIssue("この期間のデータがありません。\(window.earliestRequestedDate.label)〜\(window.endDate.label)から選んでください。")
        }
        let dates = window.dates.filter { $0 >= requested }
        guard !dates.isEmpty else { throw DataIssue("比較できる共通日がありません。") }
        return dates
    }
}

nonisolated enum SimulationCalculator {
    static func calculate(_ input: SimulationInput, dataset: ValidatedDataset) throws -> SimulationResult {
        guard (1...AppConfiguration.maximumAmount).contains(input.amount) else {
            throw DataIssue("投資金額は1円〜10億円で入力してください。")
        }
        let selected = try dataset.funds(for: input.fundIDs ?? dataset.defaultSelection)
        let requested = try TradingDay(input.requestedDate)
        let dates = try ComparisonDateResolver.dates(for: requested, in: try dataset.window(for: selected))
        guard let start = dates.first, let end = dates.last else { throw DataIssue("比較期間がありません。") }
        let principal = Decimal(input.amount)
        let results = try selected.map { fund in
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
        return SimulationResult(
            isSample: dataset.snapshot.manifest.isSample,
            input: input, requestedDate: requested, startDate: start, endDate: end, funds: results,
            displayedDifference: results.count == 2
                ? results[1].displayedValuation - results[0].displayedValuation : 0)
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
