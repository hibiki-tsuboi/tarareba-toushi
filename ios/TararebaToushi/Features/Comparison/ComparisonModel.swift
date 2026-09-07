import Foundation
import Observation

@MainActor @Observable
final class ComparisonModel {
    var amountText: String
    var selectedDate: Date
    private(set) var result: SimulationResult?
    private(set) var inputError: String?
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
        let amount = saved?.amount ?? AppConfiguration.initialAmount
        amountText = MoneyFormat.number(Decimal(amount))
        // Constants are parsed through the same strict path as remote civil dates.
        selectedDate = (try? TradingDay(saved?.requestedDate ?? AppConfiguration.initialDate).date) ?? Date()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                amountText = ProcessInfo.processInfo.environment["TARAREBA_TEST_AMOUNT"] ?? "1,000,000"
                selectedDate =
                    (try? TradingDay(
                        ProcessInfo.processInfo.environment["TARAREBA_TEST_DATE"] ?? AppConfiguration.initialDate
                    )
                    .date) ?? selectedDate
            }
        #endif
    }

    func recalculate(dataset: ValidatedDataset?) {
        result = nil
        inputError = nil
        guard let dataset else { return }
        do {
            let input = SimulationInput(
                amount: try MoneyFormat.parseAmount(amountText),
                requestedDate: try TradingDay(date: selectedDate).rawValue)
            result = try SimulationCalculator.calculate(input, dataset: dataset)
            defaults.set(try JSONEncoder().encode(input), forKey: "comparison.input.v1")
        } catch { inputError = error.localizedDescription }
    }

    func finishAmountEditing() {
        if let amount = try? MoneyFormat.parseAmount(amountText) {
            amountText = MoneyFormat.number(Decimal(amount))
        }
    }

    func preset(years: Int, dataset: ValidatedDataset?) -> TradingDay? {
        guard let dataset, let day = try? dataset.endDate.yearsBefore(years),
            day >= dataset.earliestRequestedDate, day <= dataset.endDate
        else { return nil }
        return day
    }
}
