import Foundation
import Testing

@testable import TararebaToushi

@MainActor struct ValuationChartTests {
    private func series(_ amounts: [Decimal]) throws -> [ValuationPoint] {
        let start = try TradingDay("2018-01-01")
        return try amounts.enumerated().map { offset, amount in
            guard let date = TradingDay.calendar.date(byAdding: .day, value: offset, to: start.date) else {
                throw DataIssue("日付を作れませんでした。")
            }
            return ValuationPoint(day: try TradingDay(date: date), amount: amount)
        }
    }

    @Test func shortSeriesAreDrawnPointForPoint() throws {
        let points = try series((0..<ValuationChartView.plottedPointLimit).map { Decimal(1_000_000 + $0) })
        #expect(ValuationChartView.thinned(points).map(\.day) == points.map(\.day))
    }

    @Test func thinningKeepsTheEndsThePeakAndTheTrough() throws {
        var amounts = (0..<2_000).map { Decimal(1_000_000 + $0 % 7 * 1_000) }
        amounts[911] = 9_999_999
        amounts[1_303] = 1
        let points = try series(amounts)
        let drawn = ValuationChartView.thinned(points)

        #expect(drawn.count <= ValuationChartView.plottedPointLimit + 2)
        #expect(drawn.first?.day == points.first?.day)
        #expect(drawn.last?.day == points.last?.day)
        // A peak or a trough dropped from the line would understate how far a fund moved.
        #expect(drawn.contains { $0.day == points[911].day && $0.amount == 9_999_999 })
        #expect(drawn.contains { $0.day == points[1_303].day && $0.amount == 1 })
        // Days stay in order, and every amount is the one recorded for that day.
        #expect(drawn.map(\.day) == drawn.map(\.day).sorted())
        #expect(Set(drawn.map(\.day)).count == drawn.count)
        let recorded = Dictionary(uniqueKeysWithValues: points.map { ($0.day, $0.amount) })
        #expect(drawn.allSatisfy { recorded[$0.day] == $0.amount })
    }

    @Test func thePrincipalRisesStraightUpOnPurchaseDaysOnly() throws {
        let dates = ["2025-01-06", "2025-01-20", "2025-02-06", "2025-03-06", "2025-03-10"]
        let dataset = try Fixtures.dataset([
            (id: "fund-a", dates: dates, values: ["10000", "11000", "5000", "20000", "12000"])
        ])
        let monthly = try SimulationCalculator.calculate(
            .init(amount: 10_000, requestedDate: "2025-01-06", plan: .monthly), dataset: dataset)
        let steps = ValuationChartView.principalSteps(monthly)
        // Every rise shares its date with the level before it, and the last level runs to the end.
        #expect(steps.map(\.day.rawValue)
            == ["2025-01-06", "2025-02-06", "2025-02-06", "2025-03-06", "2025-03-06", "2025-03-10"])
        #expect(steps.map(\.amount) == [10_000, 10_000, 20_000, 20_000, 30_000, 30_000])

        // Instalments that land on one day make a single rise.
        let together = try SimulationCalculator.calculate(
            .init(amount: 30_000, requestedDate: "2025-01-01", plan: .monthly), dataset: Fixtures.validated())
        #expect(ValuationChartView.principalSteps(together).map(\.amount) == [30_000, 30_000, 630_000])

        // A principal that never changes is drawn as a rule instead.
        let lumpSum = try SimulationCalculator.calculate(
            .init(amount: 10_000, requestedDate: "2025-01-06"), dataset: dataset)
        #expect(ValuationChartView.principalSteps(lumpSum).isEmpty)
    }
}
