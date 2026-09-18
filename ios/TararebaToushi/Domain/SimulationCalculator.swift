import Foundation

nonisolated enum InvestmentPlan: String, CaseIterable, Codable, Sendable {
    case lumpSum
    case monthly

    var label: String {
        switch self {
        case .lumpSum: "一括投資"
        case .monthly: "毎月積立"
        }
    }
}

nonisolated struct SimulationInput: Codable, Sendable {
    // The whole sum for a lump sum; each instalment for a monthly plan.
    var amount: Int
    var requestedDate: String
    // Absent in snapshots saved before selection existed; nil means the default pair.
    var fundIDs: [String]? = nil
    // Absent in inputs saved before monthly plans existed; nil means a lump sum.
    var plan: InvestmentPlan? = nil
}

nonisolated struct ValuationPoint: Identifiable, Sendable {
    var id: String { day.rawValue }
    let day: TradingDay
    let amount: Decimal
}

// The day a holding stood furthest below what had been paid in by then.
nonisolated struct DeepestLoss: Equatable, Sendable {
    let day: TradingDay
    // Negative: that day's displayed valuation less the principal paid in by then.
    let displayedAmount: Decimal

    var label: String { "\(MoneyFormat.signed(displayedAmount))円（\(day.label)）" }
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
    // The same principal paid in at once on the start day. For a lump sum, the valuation itself.
    let lumpSumValuation: Decimal
    let displayedLumpSumValuation: Decimal
    // nil when the displayed valuation never fell below the principal paid in by then.
    let deepestLoss: DeepestLoss?
    let lumpSumDeepestLoss: DeepestLoss?

    var shortName: String { descriptor.shortName }
    // Positive when paying everything in on the start day would have ended ahead.
    var displayedLumpSumAdvantage: Decimal { displayedLumpSumValuation - displayedValuation }
}

nonisolated struct SimulationResult: Sendable {
    let isSample: Bool
    let input: SimulationInput
    let requestedDate: TradingDay
    let startDate: TradingDay
    let endDate: TradingDay
    // Common days, so every fund buys on the same days. A lump sum buys once, on the start day.
    let purchaseDays: [TradingDay]
    let funds: [FundResult]
    // Signed, and only meaningful for exactly two funds: funds[1] - funds[0].
    let displayedDifference: Decimal

    var plan: InvestmentPlan { input.plan ?? .lumpSum }
    var principal: Decimal { Decimal(input.amount) * Decimal(purchaseDays.count) }
    // Instalments that were all bought on the start day are the lump sum already.
    var comparesWithLumpSum: Bool { plan == .monthly && purchaseDays.last != startDate }

    // Everything paid in up to and including that day.
    func principal(on day: TradingDay) -> Decimal {
        Decimal(input.amount) * Decimal(purchaseDays.filter { $0 <= day }.count)
    }

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

    // An instalment falls on the requested day of each month, or on the last day of a
    // shorter month, and is bought on the first common day from then on. One that finds
    // no common day before the next is due is bought with it, on the day that comes.
    static func purchaseDays(for plan: InvestmentPlan, from requested: TradingDay, in dates: [TradingDay])
        -> [TradingDay]
    {
        guard plan == .monthly else { return Array(dates.prefix(1)) }
        let calendar = TradingDay.calendar
        var days: [TradingDay] = []
        var next = dates.startIndex
        for month in 0... {
            // Counted from the requested day every time, so the 31st returns after February.
            guard let scheduled = calendar.date(byAdding: .month, value: month, to: requested.date),
                let index = dates[next...].firstIndex(where: { $0.date >= scheduled })
            else { break }
            days.append(dates[index])
            next = index
        }
        return days
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
        let plan = input.plan ?? .lumpSum
        let purchases = ComparisonDateResolver.purchaseDays(for: plan, from: requested, in: dates)
        let instalment = Decimal(input.amount)
        let principal = instalment * Decimal(purchases.count)
        let results = try selected.map { fund in
            guard let initial = fund.values[start], initial > 0 else { throw DataIssue("開始日の値が不正です。") }
            // The holding is carried forward from the last purchase day, multiplying by the
            // day's price before dividing by that day's. A lump sum therefore stays exactly
            // principal × value ÷ initial, and an exact half yen is never a rounding error
            // short. Each instalment is worth what was paid for it on its own day.
            var held: Decimal = 0
            var basis = initial
            var pending = purchases[...]
            let points = try dates.map { day in
                guard let value = fund.values[day], value > 0 else { throw DataIssue("比較日の値が不正です。") }
                let bought = pending.prefix { $0 == day }.count
                guard bought > 0 else { return ValuationPoint(day: day, amount: held * value / basis) }
                pending = pending.dropFirst(bought)
                held = held * value / basis + instalment * Decimal(bought)
                basis = value
                return ValuationPoint(day: day, amount: held)
            }
            guard let last = points.last, let endValue = fund.values[end], !last.amount.isNaN else {
                throw DataIssue("評価額を計算できませんでした。")
            }
            let rounded = MoneyFormat.round(last.amount)
            // The lump sum's own expression, so for a lump sum it is the valuation to the last digit.
            let lumpSum = principal * endValue / initial
            let deepest = deepestLoss(of: points, buying: purchases, instalment: instalment)
            var lumpSumDeepest = deepest
            if plan == .monthly {
                // The same principal paid in on the start day, priced every day as a lump sum is.
                let lumpSumPoints = try dates.map { day in
                    guard let value = fund.values[day] else { throw DataIssue("比較日の値が不正です。") }
                    return ValuationPoint(day: day, amount: principal * value / initial)
                }
                lumpSumDeepest = deepestLoss(of: lumpSumPoints, buying: [start], instalment: principal)
            }
            return FundResult(
                descriptor: fund.descriptor, points: points, valuation: last.amount,
                profit: last.amount - principal,
                // Instalments bought at later prices do not earn the fund's own change.
                returnPercent: plan == .lumpSum
                    ? (endValue / initial - 1) * 100 : (last.amount / principal - 1) * 100,
                displayedValuation: rounded, displayedProfit: rounded - principal,
                lumpSumValuation: lumpSum, displayedLumpSumValuation: MoneyFormat.round(lumpSum),
                deepestLoss: deepest, lumpSumDeepestLoss: lumpSumDeepest)
        }
        return SimulationResult(
            isSample: dataset.snapshot.manifest.isSample,
            input: input, requestedDate: requested, startDate: start, endDate: end,
            purchaseDays: purchases, funds: results,
            displayedDifference: results.count == 2
                ? results[1].displayedValuation - results[0].displayedValuation : 0)
    }

    // The day the displayed valuation stood furthest below the principal paid in by then,
    // the earlier day on a tie, and nil when it never fell below. Displayed amounts are
    // compared, as everywhere else, so a fraction of a yen below the principal is no loss.
    private static func deepestLoss(
        of points: [ValuationPoint], buying purchases: [TradingDay], instalment: Decimal
    ) -> DeepestLoss? {
        var deepest: DeepestLoss?
        var bought = 0
        for point in points {
            while bought < purchases.count, purchases[bought] <= point.day { bought += 1 }
            let loss = MoneyFormat.round(point.amount) - instalment * Decimal(bought)
            if loss < (deepest?.displayedAmount ?? 0) { deepest = DeepestLoss(day: point.day, displayedAmount: loss) }
        }
        return deepest
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
