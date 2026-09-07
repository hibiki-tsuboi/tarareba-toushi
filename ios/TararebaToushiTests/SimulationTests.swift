import Foundation
import Testing

@testable import TararebaToushi

struct SimulationTests {
    @Test(arguments: [DatasetMode.live, .sample])
    func comparisonUsesTheFullAmountForBothFundsInFixedOrder(mode: DatasetMode) throws {
        var snapshot = Fixtures.snapshot(mode: mode)
        snapshot.manifest.funds.reverse()
        snapshot.series.reverse()
        let dataset = try DatasetValidator.validate(snapshot, mode: mode)
        let input = SimulationInput(
            amount: 1_000_000, requestedDate: "2025-01-01", fundIDs: mode.fundIDs.reversed())
        let result = try SimulationCalculator.calculate(input, dataset: dataset)
        // Neither the catalog order nor the request order changes the displayed order.
        #expect(result.funds.map(\.id) == mode.fundIDs)
        #expect(result.funds.map(\.displayedValuation) == [1_200_000, 1_400_000, 1_300_000, 1_600_000, 1_500_000])
        #expect(result.funds.map(\.displayedProfit) == [200_000, 400_000, 300_000, 600_000, 500_000])
        #expect(result.funds.allSatisfy { $0.points.first?.amount == 1_000_000 })
        #expect(result.funds[0].points.map(\.day) == result.funds[1].points.map(\.day))
        #expect(result.startDate.rawValue == "2025-01-06")
    }

    @Test func expectedReturnsAndDifference() throws {
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-01"), dataset: Fixtures.validated())
        #expect(result.startDate.rawValue == "2025-01-06")
        #expect(result.funds[0].valuation == 1_200_000)
        #expect(result.funds[0].profit == 200_000)
        #expect(result.funds[0].returnPercent == 20)
        #expect(result.funds[1].valuation == 1_400_000)
        #expect(result.funds[1].returnPercent == 40)
        #expect(result.displayedDifference == 200_000)
        #expect(result.funds.allSatisfy { $0.points.first?.amount == 1_000_000 })
        let doubled = try SimulationCalculator.calculate(
            .init(amount: 2_000_000, requestedDate: "2025-01-01"), dataset: Fixtures.validated())
        #expect(doubled.funds[0].valuation == result.funds[0].valuation * 2)
        #expect(doubled.displayedDifference == result.displayedDifference * 2)
        #expect(doubled.funds[1].returnPercent == result.funds[1].returnPercent)
    }

    @Test func lossesFlatAndOnePoint() throws {
        let dataset = try Fixtures.validated(Fixtures.snapshot(a: "8000", b: "10000"))
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06"), dataset: dataset)
        #expect(result.funds[0].valuation == 800_000)
        #expect(result.funds[0].profit == -200_000)
        #expect(result.funds[0].returnPercent == -20)
        #expect(result.funds[1].profit == 0)
        let one = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2026-09-04"), dataset: dataset)
        #expect(one.funds.allSatisfy { $0.points.count == 1 && $0.profit == 0 })
        #expect(one.displayedDifference == 0)
    }

    @Test func roundedDisplayRemainsConsistent() throws {
        let dataset = try Fixtures.validated(Fixtures.snapshot(a: "10000.004000", b: "10000.004900"))
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06"), dataset: dataset)
        #expect(result.funds[0].valuation != result.funds[1].valuation)
        #expect(result.displayedDifference == 0)
        #expect(result.funds.allSatisfy { $0.displayedProfit == $0.displayedValuation - 1_000_000 })
        #expect(MoneyFormat.round(Decimal(string: "1.5") ?? 0) == 2)
        #expect(MoneyFormat.signed(Decimal(string: "-0.01") ?? 0, digits: 1) == "0.0")
    }

    @Test func selectingOneFundDropsTheComparison() throws {
        let dataset = try Fixtures.validated()
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06", fundIDs: ["demo-sp500"]), dataset: dataset)
        #expect(result.funds.map(\.id) == ["demo-sp500"])
        #expect(result.funds[0].displayedValuation == 1_400_000)
        #expect(result.displayedDifference == 0)
        #expect(result.displayedSpread == 0)
    }

    @Test func selectionKeepsDeliveredOrderRegardlessOfRequestOrder() throws {
        let dataset = try Fixtures.validated()
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06", fundIDs: ["demo-sp500", "demo-all-country"]),
            dataset: dataset)
        #expect(result.funds.map(\.id) == ["demo-all-country", "demo-sp500"])
        #expect(result.displayedDifference == 200_000)
    }

    @Test func unknownAndOversizedSelectionsAreRejected() throws {
        let dataset = try Fixtures.validated()
        #expect(throws: DataIssue.self) {
            try SimulationCalculator.calculate(
                .init(amount: 1_000_000, requestedDate: "2025-01-06", fundIDs: ["demo-nikkei"]), dataset: dataset)
        }
        let dates = ["2025-01-06", "2026-09-04"]
        let many = try Fixtures.dataset((0...5).map {
            (id: "fund-\($0)", dates: dates, values: ["10000", "11000"])
        })
        #expect(throws: DataIssue.self) { try many.funds(for: many.funds.map(\.descriptor.id)) }
        #expect(try many.funds(for: Array(many.funds.prefix(5).map(\.descriptor.id))).count == 5)
    }

    @Test func aShortHistoryOnlyLimitsTheFundsItIsComparedWith() throws {
        let long = ["2020-01-06", "2025-01-06", "2026-09-04"]
        let dataset = try Fixtures.dataset([
            (id: "old-a", dates: long, values: ["10000", "12000", "15000"]),
            (id: "old-b", dates: long, values: ["10000", "11000", "13000"]),
            (id: "new-c", dates: ["2025-01-06", "2026-09-04"], values: ["10000", "20000"]),
        ])
        #expect(try dataset.window(for: ["old-a", "old-b"]).earliestRequestedDate.rawValue == "2020-01-06")
        #expect(try dataset.window(for: ["old-a", "new-c"]).earliestRequestedDate.rawValue == "2025-01-06")
        #expect(try dataset.window(for: ["old-a"]).dates.count == 3)
        // The whole-catalog intersection must not decide the period of a pair.
        #expect(try dataset.window(for: ["old-a", "old-b"]).dates.count == 3)
    }

    @Test func threeFundsRankByValuationAndReportTheWidestGap() throws {
        let dates = ["2025-01-06", "2026-09-04"]
        let dataset = try Fixtures.dataset([
            (id: "fund-a", dates: dates, values: ["10000", "12000"]),
            (id: "fund-b", dates: dates, values: ["10000", "9000"]),
            (id: "fund-c", dates: dates, values: ["10000", "15000"]),
        ])
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06", fundIDs: ["fund-a", "fund-b", "fund-c"]),
            dataset: dataset)
        #expect(result.funds.map(\.id) == ["fund-a", "fund-b", "fund-c"])
        #expect(result.ranking.map(\.id) == ["fund-c", "fund-a", "fund-b"])
        #expect(result.displayedSpread == 600_000)
        #expect(result.displayedDifference == 0)
    }

    @Test(arguments: [0, -1, 1_000_000_001]) func invalidAmounts(amount: Int) throws {
        let dataset = try Fixtures.validated()
        #expect(throws: DataIssue.self) {
            try SimulationCalculator.calculate(.init(amount: amount, requestedDate: "2025-01-06"), dataset: dataset)
        }
    }

    @Test(arguments: ["", "0", "-1", "1.5", "12円", "1e6", "1000000001"])
    func invalidInput(text: String) { #expect(throws: DataIssue.self) { try MoneyFormat.parseAmount(text) } }

    @Test func fullWidthAmountAndMaximum() throws {
        #expect(try MoneyFormat.parseAmount("１，０００，０００") == 1_000_000)
        #expect(try MoneyFormat.parseAmount("1,000,000,000") == 1_000_000_000)
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000_000, requestedDate: "2025-01-06"), dataset: Fixtures.validated())
        #expect(result.funds[1].valuation == 1_400_000_000)
    }

    @Test func actualIntersectionNotMinimumLastDate() throws {
        var snapshot = Fixtures.snapshot()
        snapshot.series[0].observations = [
            .init(date: "2025-01-06", value: "100"), .init(date: "2026-09-02", value: "120"),
            .init(date: "2026-09-04", value: "130"),
        ]
        snapshot.series[1].observations = [
            .init(date: "2025-01-06", value: "100"), .init(date: "2026-09-02", value: "140"),
            .init(date: "2026-09-03", value: "150"),
        ]
        for i in 0..<2 {
            snapshot.manifest.funds[i].firstDate = "2025-01-06"
            snapshot.manifest.funds[i].lastDate = snapshot.series[i].observations.last?.date ?? ""
        }
        let result = try SimulationCalculator.calculate(
            .init(amount: 100, requestedDate: "2025-01-06"), dataset: Fixtures.validated(snapshot))
        #expect(result.endDate.rawValue == "2026-09-02")
        #expect(result.funds[0].valuation == 120)
        #expect(result.funds[1].valuation == 140)
    }

    @Test(arguments: ["2020-01-01", "2026-09-05"])
    func unavailablePeriod(date: String) throws {
        let dataset = try Fixtures.validated()
        let window = try dataset.window(for: dataset.defaultSelection)
        #expect(throws: DataIssue.self) { try ComparisonDateResolver.dates(for: TradingDay(date), in: window) }
    }

    @Test(arguments: ["2025-02-30", "2025-02-29", "2026-13-01", "2025-1-01", "2025-01-00", "0000-01-01"])
    func invalidDates(date: String) { #expect(throws: DataIssue.self) { try TradingDay(date) } }

    @Test func leapYearAndTokyoDates() throws {
        let leap = try TradingDay("2024-02-29")
        #expect(try leap.yearsBefore(1).rawValue == "2023-02-28")
        #expect(try leap.yearsBefore(3).rawValue == "2021-02-28")
        #expect(try TradingDay(date: leap.date) == leap)
        let instant = try #require(ISO8601DateFormatter().date(from: "2025-01-01T16:00:00Z"))
        #expect(try TradingDay(date: instant).rawValue == "2025-01-02")
    }

    @Test func rejectsInvalidDatasets() throws {
        let mutations: [(inout DatasetSnapshot) -> Void] = [
            { $0.manifest.schemaVersion = 2 }, { $0.manifest.isSample = false },
            { $0.manifest.funds[0].currency = "USD" }, { $0.manifest.funds[0].path = "https://evil.example/data.json" },
            { $0.manifest.funds[0].path = "../test.json" }, { $0.manifest.funds[0].path = "funds/%2e%2e/test.json" },
            { $0.manifest.funds[1].id = $0.manifest.funds[0].id }, { $0.series[0].valueBasis = "unknown" },
            { $0.series[0].isSample = false }, { $0.series[0].datasetVersion = "sample-v9" },
            { $0.series[0].currency = "USD" }, { $0.series[0].fundId = "wrong" },
            { $0.series[0].observations = [] }, { $0.series[0].observations[0].date = "2025-02-30" },
            { $0.series[0].observations[1].date = "2024-12-30" }, { $0.series[0].observations.reverse() },
            { $0.manifest.funds[0].lastDate = "2026-09-03" },
        ]
        for mutate in mutations {
            var snapshot = Fixtures.snapshot()
            mutate(&snapshot)
            #expect(throws: DataIssue.self) { try Fixtures.validated(snapshot) }
        }
    }

    @Test(arguments: ["0", "-1", "NaN", "Infinity", "1e4", "123abc", "1000000000000", "0.0000001"])
    func invalidSeriesValues(value: String) { #expect(throws: DataIssue.self) { try DatasetValidator.decimal(value) } }

    @Test func noCommonDates() {
        var snapshot = Fixtures.snapshot()
        snapshot.series[1].observations = [.init(date: "2025-01-07", value: "100")]
        snapshot.manifest.funds[1].firstDate = "2025-01-07"
        snapshot.manifest.funds[1].lastDate = "2025-01-07"
        #expect(throws: DataIssue.self) { try Fixtures.validated(snapshot) }
    }
}
