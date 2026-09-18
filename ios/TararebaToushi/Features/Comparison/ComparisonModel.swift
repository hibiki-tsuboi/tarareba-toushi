import Foundation
import Observation

@MainActor @Observable
final class ComparisonModel {
    var amountText: String
    var selectedDate: Date
    private(set) var plan: InvestmentPlan
    private(set) var selection: [String]
    private(set) var result: SimulationResult?
    private(set) var inputError: String?
    // The plan not on screen keeps its own amount: a lump sum and a monthly instalment
    // differ by orders of magnitude, so neither makes a sensible default for the other.
    @ObservationIgnored private var otherAmountText: String
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        var preferences = defaults ?? .standard
        #if DEBUG
            if defaults == nil, ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let session = ProcessInfo.processInfo.environment["TARAREBA_TEST_SESSION"] ?? UUID().uuidString
                preferences = UserDefaults(suiteName: "UITests.\(session)") ?? preferences
            }
        #endif
        self.defaults = preferences
        let saved = preferences.data(forKey: "comparison.input.v1")
            .flatMap { try? JSONDecoder().decode(SimulationInput.self, from: $0) }
        let plan = saved?.plan ?? .lumpSum
        self.plan = plan
        let amount = saved?.amount ?? Self.initialAmount(for: plan)
        amountText = MoneyFormat.number(Decimal(amount))
        otherAmountText = MoneyFormat.number(Decimal(Self.initialAmount(for: plan == .lumpSum ? .monthly : .lumpSum)))
        // Constants are parsed through the same strict path as remote civil dates.
        selectedDate = (try? TradingDay(saved?.requestedDate ?? AppConfiguration.initialDate).date) ?? Date()
        // Empty means "not chosen yet"; the dataset decides the default pair.
        selection = saved?.fundIDs ?? []
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                amountText =
                    ProcessInfo.processInfo.environment["TARAREBA_TEST_AMOUNT"]
                    ?? MoneyFormat.number(Decimal(Self.initialAmount(for: plan)))
                selectedDate =
                    (try? TradingDay(
                        ProcessInfo.processInfo.environment["TARAREBA_TEST_DATE"] ?? AppConfiguration.initialDate
                    )
                    .date) ?? selectedDate
            }
        #endif
    }

    // Selections are kept in delivered order so colours match the result cards.
    func selectedIDs(in dataset: ValidatedDataset) -> [String] {
        let chosen = Set(selection)
        let known = dataset.funds.map(\.descriptor.id).filter { chosen.contains($0) }
        return known.isEmpty ? dataset.defaultSelection : known
    }

    func toggle(_ id: String, in dataset: ValidatedDataset) {
        var chosen = Set(selectedIDs(in: dataset))
        if chosen.contains(id) {
            guard chosen.count > 1 else {
                inputError = "商品を1つ以上選んでください。"
                return
            }
            chosen.remove(id)
        } else {
            guard chosen.count < AppConfiguration.maximumComparisonFunds else {
                inputError = "同時に比較できるのは\(AppConfiguration.maximumComparisonFunds)商品までです。"
                return
            }
            chosen.insert(id)
        }
        inputError = nil
        selection = dataset.funds.map(\.descriptor.id).filter { chosen.contains($0) }
    }

    func select(_ plan: InvestmentPlan) {
        guard plan != self.plan else { return }
        finishAmountEditing()
        (amountText, otherAmountText) = (otherAmountText, amountText)
        self.plan = plan
        inputError = nil
    }

    func recalculate(dataset: ValidatedDataset?) {
        result = nil
        inputError = nil
        guard let dataset else { return }
        do {
            let input = SimulationInput(
                amount: try MoneyFormat.parseAmount(amountText),
                requestedDate: try TradingDay(date: selectedDate).rawValue,
                fundIDs: selectedIDs(in: dataset), plan: plan)
            result = try SimulationCalculator.calculate(input, dataset: dataset)
            defaults.set(try JSONEncoder().encode(input), forKey: "comparison.input.v1")
        } catch { inputError = error.localizedDescription }
    }

    func finishAmountEditing() {
        if let amount = try? MoneyFormat.parseAmount(amountText) {
            amountText = MoneyFormat.number(Decimal(amount))
        }
    }

    private static func initialAmount(for plan: InvestmentPlan) -> Int {
        plan == .monthly ? AppConfiguration.initialMonthlyAmount : AppConfiguration.initialAmount
    }
}
