import Foundation
import Testing

@testable import TararebaToushi

struct DeepestLossTests {
    @Test func instalmentsSinkLessThanTheLumpSumThroughTheSameDip() throws {
        let result = try SimulationCalculator.calculate(
            .init(amount: 10_000, requestedDate: "2025-01-06", fundIDs: ["fund-a", "fund-b"], plan: .monthly),
            dataset: Fixtures.dipAndRecovery())
        // In February the instalments were worth 15,000 against 20,000 paid in, while the
        // 30,000 paid in at once had halved to 15,000.
        #expect(result.funds[0].deepestLoss?.day.rawValue == "2025-02-06")
        #expect(result.funds[0].deepestLoss?.displayedAmount == -5_000)
        #expect(result.funds[0].lumpSumDeepestLoss?.day.rawValue == "2025-02-06")
        #expect(result.funds[0].lumpSumDeepestLoss?.displayedAmount == -15_000)
        #expect(result.funds[0].deepestLoss?.label == "−5,000円（2025/02/06）")
        // A fund that never moves never falls below what was paid in.
        #expect(result.funds[1].deepestLoss == nil)
        #expect(result.funds[1].lumpSumDeepestLoss == nil)
    }

    @Test func aLumpSumIsItsOwnLumpSumAndATieGoesToTheEarlierDay() throws {
        let dataset = try Fixtures.dataset([
            (id: "fund-a", dates: ["2025-01-06", "2025-01-07", "2025-01-08", "2025-01-09"],
                values: ["10000", "9000", "9000", "10000"])
        ])
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06"), dataset: dataset)
        #expect(result.funds[0].deepestLoss?.day.rawValue == "2025-01-07")
        #expect(result.funds[0].deepestLoss?.displayedAmount == -100_000)
        #expect(result.funds[0].lumpSumDeepestLoss?.day == result.funds[0].deepestLoss?.day)
        #expect(result.funds[0].lumpSumDeepestLoss?.displayedAmount == -100_000)
        // Recovered by the last day, the result still shows how deep it went.
        #expect(result.funds[0].displayedProfit == 0)
    }

    @Test func lessThanAYenBelowThePrincipalIsNoLoss() throws {
        let dataset = try Fixtures.dataset([
            (id: "fund-a", dates: ["2025-01-06", "2025-01-07", "2025-01-08"], values: ["10000", "9999.999", "10000"])
        ])
        // 1,000 × 9,999.999 ÷ 10,000 is 999.9999 yen, shown as 1,000 yen.
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000, requestedDate: "2025-01-06"), dataset: dataset)
        #expect(result.funds[0].points[1].amount < 1_000)
        #expect(result.funds[0].deepestLoss == nil)
    }
}
