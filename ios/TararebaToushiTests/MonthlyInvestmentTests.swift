import Foundation
import Testing

@testable import TararebaToushi

@MainActor struct MonthlyInvestmentTests {
    private func monthly(
        _ amount: Int, from date: String, in dataset: ValidatedDataset, funds: [String]? = nil
    ) throws -> SimulationResult {
        try SimulationCalculator.calculate(
            .init(amount: amount, requestedDate: date, fundIDs: funds, plan: .monthly), dataset: dataset)
    }

    private func purchases(from requested: String, in dates: [String]) throws -> [String] {
        let requested = try TradingDay(requested)
        let days = try dates.map { try TradingDay($0) }.filter { $0 >= requested }
        return ComparisonDateResolver.purchaseDays(for: .monthly, from: requested, in: days).map(\.rawValue)
    }

    @Test func instalmentsBoughtLowEarnMoreThanTheFundsOwnChange() throws {
        let dataset = try Fixtures.dipAndRecovery()
        let result = try monthly(10_000, from: "2025-01-06", in: dataset, funds: ["fund-a", "fund-b"])
        #expect(result.plan == .monthly)
        #expect(result.purchaseDays.map(\.rawValue) == ["2025-01-06", "2025-02-06", "2025-03-06"])
        #expect(result.principal == 30_000)
        #expect(result.principal(on: try TradingDay("2025-02-05")) == 10_000)
        #expect(result.principal(on: try TradingDay("2025-02-06")) == 20_000)
        // Each instalment is worth what was paid on its day, then moves with the price.
        #expect(result.funds[0].points.map(\.amount) == [10_000, 11_000, 15_000, 70_000, 42_000])
        #expect(result.funds[0].displayedProfit == 12_000)
        #expect(result.funds[0].returnPercent == 40)
        #expect(result.funds[1].points.map(\.amount) == [10_000, 10_000, 20_000, 30_000, 30_000])
        #expect(result.funds[1].displayedProfit == 0)
        #expect(result.displayedDifference == -12_000)
        // The price ended 20% up; the February instalment bought at half price doubled that.
        let lumpSum = try SimulationCalculator.calculate(
            .init(amount: 30_000, requestedDate: "2025-01-06", fundIDs: ["fund-a"]), dataset: dataset)
        #expect(lumpSum.funds[0].returnPercent == 20)
    }

    @Test func aMissingCommonDayDefersTheInstalmentAndShortMonthsUseTheirLastDay() throws {
        let values = Array(repeating: "10000", count: 7)
        let dataset = try Fixtures.dataset([
            (id: "fund-a", dates: [
                "2025-01-31", "2025-02-28", "2025-03-28", "2025-03-31", "2025-04-01", "2025-04-30", "2025-05-30",
            ], values: values),
            // No price on 2025-03-31, so the March instalment waits for the next common day.
            (id: "fund-b", dates: [
                "2025-01-31", "2025-02-28", "2025-03-28", "2025-04-01", "2025-04-30", "2025-05-30",
            ], values: Array(values.prefix(6))),
        ])
        let result = try monthly(10_000, from: "2025-01-31", in: dataset, funds: ["fund-a", "fund-b"])
        // May 31 comes after the last common day, so it is not bought.
        #expect(result.purchaseDays.map(\.rawValue) == ["2025-01-31", "2025-02-28", "2025-04-01", "2025-04-30"])
        #expect(result.principal == 40_000)
        #expect(result.funds.allSatisfy { $0.displayedValuation == 40_000 })
        // The day is counted from the requested date each month, so the 31st comes back.
        #expect(try purchases(from: "2024-01-31", in: ["2024-01-31", "2024-02-29", "2024-03-29", "2024-04-01"])
            == ["2024-01-31", "2024-02-29", "2024-04-01"])
        #expect(try purchases(from: "2025-02-01", in: ["2025-01-31", "2025-02-03", "2025-03-03", "2025-03-04"])
            == ["2025-02-03", "2025-03-03"])
    }

    @Test func monthsWithoutACommonDayAreBoughtTogetherOnTheNextOne() throws {
        let result = try monthly(30_000, from: "2025-01-01", in: Fixtures.validated())
        #expect(result.startDate.rawValue == "2025-01-06")
        #expect(result.purchaseDays.first?.rawValue == "2025-01-06")
        #expect(result.purchaseDays.dropFirst().allSatisfy { $0.rawValue == "2026-09-04" })
        #expect(result.purchaseDays.count == 21)
        #expect(result.principal == 630_000)
        #expect(result.funds.map(\.displayedValuation) == [636_000, 642_000])
        #expect(result.funds.map(\.displayedProfit) == [6_000, 12_000])
    }

    @Test func holdingsAreMultipliedBeforeTheyAreDivided() throws {
        let dates = ["2025-01-06", "2025-01-07", "2025-01-31", "2025-02-06"]
        let dataset = try Fixtures.dataset([
            (id: "fund-a", dates: dates, values: ["13900", "20850", "27800", "13900"])
        ])
        // 10,001 × 20,850 ÷ 13,900 is exactly 15,001.5. Dividing first would miss the half
        // yen by a rounding error and could show 15,001.
        let result = try monthly(10_001, from: "2025-01-06", in: dataset, funds: ["fund-a"])
        #expect(result.funds[0].points.map(\.amount) == [10_001, Decimal(string: "15001.5") ?? 0, 20_002, 20_002])
        #expect(MoneyFormat.round(result.funds[0].points[1].amount) == 15_002)
        // Before its second instalment a monthly plan is the same single purchase as a lump sum.
        let lumpSum = try SimulationCalculator.calculate(
            .init(amount: 10_001, requestedDate: "2025-01-06", fundIDs: ["fund-a"]), dataset: dataset)
        #expect(lumpSum.purchaseDays.map(\.rawValue) == ["2025-01-06"])
        #expect(lumpSum.principal == 10_001)
        #expect(lumpSum.funds[0].points.prefix(3).map(\.amount) == result.funds[0].points.prefix(3).map(\.amount))
        #expect(lumpSum.funds[0].points.last?.amount == 10_001)
    }

    @Test func theSamePrincipalPaidInAtOnceIsComparedFundByFund() throws {
        let result = try monthly(10_000, from: "2025-01-06", in: Fixtures.dipAndRecovery(), funds: ["fund-a", "fund-b"])
        #expect(result.comparesWithLumpSum)
        // 30,000 paid in on 01-06 rides the 20% rise, but the February instalment bought at half price.
        #expect(result.funds.map(\.displayedLumpSumValuation) == [36_000, 30_000])
        #expect(result.funds.map(\.displayedLumpSumAdvantage) == [-6_000, 0])

        let rising = try monthly(30_000, from: "2025-01-01", in: Fixtures.validated())
        #expect(rising.funds.map(\.displayedLumpSumValuation) == [756_000, 882_000])
        #expect(rising.funds.map(\.displayedLumpSumAdvantage) == [120_000, 240_000])
    }

    @Test func instalmentsBoughtOnlyOnTheStartDayAreTheLumpSumAlready() throws {
        let dataset = try Fixtures.validated()
        let once = try monthly(30_000, from: "2026-09-04", in: dataset)
        #expect(!once.comparesWithLumpSum)
        #expect(once.funds.allSatisfy { $0.lumpSumValuation == $0.valuation })
        // Two instalments waiting for the first common day are one purchase of both.
        let waiting = try Fixtures.dataset([
            (id: "fund-a", dates: ["2024-11-29", "2025-01-06"], values: ["10000", "12000"])
        ])
        let both = try monthly(30_000, from: "2024-12-01", in: waiting)
        #expect(both.purchaseDays.map(\.rawValue) == ["2025-01-06", "2025-01-06"])
        #expect(!both.comparesWithLumpSum)
        #expect(both.funds[0].displayedLumpSumAdvantage == 0)
        // A lump sum has nothing to compare with and is its own lump sum to the last digit.
        let lumpSum = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-01"), dataset: dataset)
        #expect(!lumpSum.comparesWithLumpSum)
        #expect(lumpSum.funds.allSatisfy { $0.lumpSumValuation == $0.valuation })
    }

    @Test func eachPlanKeepsItsOwnAmountAndTheLastSimulatedPlanIsRestored() throws {
        let name = "tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let dataset = try Fixtures.validated()
        let model = ComparisonModel(defaults: defaults)
        #expect(model.plan == .lumpSum)
        #expect(model.amountText == "1,000,000")

        model.select(.monthly)
        #expect(model.amountText == "30,000")
        model.amountText = "50000"
        model.select(.lumpSum)
        #expect(model.amountText == "1,000,000")
        model.select(.monthly)
        #expect(model.amountText == "50,000")

        model.recalculate(dataset: dataset)
        #expect(model.result?.plan == .monthly)
        #expect(model.result?.input.amount == 50_000)
        #expect(model.result?.principal == 1_050_000)
        let restored = ComparisonModel(defaults: defaults)
        #expect(restored.plan == .monthly)
        #expect(restored.amountText == "50,000")
        restored.select(.lumpSum)
        #expect(restored.amountText == "1,000,000")
    }
}
