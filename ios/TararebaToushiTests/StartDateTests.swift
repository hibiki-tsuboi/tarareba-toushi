import Foundation
import Testing

@testable import TararebaToushi

@MainActor struct StartDateTests {
    // old-a and old-b go back further than new-c; each misses a day the others have.
    private func staggered() throws -> ValidatedDataset {
        try Fixtures.dataset([
            (id: "old-a", dates: ["2020-01-06", "2021-01-04", "2024-01-04", "2024-01-05"],
                values: ["10000", "11000", "12000", "13000"]),
            (id: "old-b", dates: ["2019-01-04", "2021-01-04", "2024-01-05"], values: ["10000", "11000", "12000"]),
            (id: "new-c", dates: ["2021-01-04", "2024-01-04", "2024-01-08"], values: ["10000", "11000", "12000"]),
        ])
    }

    @Test func theRangeOfferedIsTheOneTheCalculationEnforces() throws {
        let dataset = try staggered()
        for ids in [["old-a", "old-b"], ["old-a", "new-c"], ["old-b", "new-c"], ["old-a", "old-b", "new-c"], ["new-c"]] {
            let range = try dataset.startRange(for: ids)
            let window = try dataset.window(for: ids)
            #expect(range.lowerBound == window.earliestRequestedDate)
            #expect(range.upperBound == window.endDate)
        }
        // old-b and new-c share only 2021-01-04: each misses the other's last day.
        #expect(try dataset.startRange(for: ["old-b", "new-c"]) == TradingDay("2021-01-04")...TradingDay("2021-01-04"))
    }

    @Test func addingAYoungerFundMovesAnEarlierDateToWhereItsHistoryBegins() throws {
        let name = "tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let dataset = try staggered()
        let model = ComparisonModel(defaults: defaults)
        model.selectedDate = try TradingDay("2020-06-01").date
        model.fitDate(in: dataset)
        #expect(model.adjustedDate == nil)

        model.toggle("new-c", in: dataset)
        #expect(try TradingDay(date: model.selectedDate).rawValue == "2021-01-04")
        #expect(model.adjustedDate == model.selectedDate)
        // Taking it away again widens the period without moving the date, and the notice goes.
        model.toggle("new-c", in: dataset)
        #expect(try TradingDay(date: model.selectedDate).rawValue == "2021-01-04")
        #expect(model.adjustedDate == nil)

        model.selectedDate = try TradingDay("2026-09-18").date
        model.fitDate(in: dataset)
        #expect(try TradingDay(date: model.selectedDate).rawValue == "2024-01-05")
        #expect(model.adjustedDate == model.selectedDate)
    }

    @Test func selectionLimitsAreReportedToThePicker() throws {
        let name = "tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let dataset = try Fixtures.validated()
        let model = ComparisonModel(defaults: defaults)
        model.toggle("demo-all-country", in: dataset)
        model.toggle("demo-sp500", in: dataset)
        #expect(model.selectionMessage == "商品を1つ以上選んでください。")
        #expect(model.inputError == nil)
        model.clearSelectionMessage()
        #expect(model.selectionMessage == nil)
        for id in dataset.funds.map(\.descriptor.id) where id != "demo-sp500" {
            model.toggle(id, in: dataset)
        }
        #expect(model.selectedIDs(in: dataset).count == AppConfiguration.maximumComparisonFunds)
        #expect(model.selectionMessage == "同時に比較できるのは\(AppConfiguration.maximumComparisonFunds)商品までです。")
    }
}
