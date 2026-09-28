import Foundation
import Testing

@testable import TararebaToushi

// The catalog decides which products exist. This version offers the ones it can compute
// and leaves the rest out, so a later catalog never breaks it.
@MainActor struct CatalogTests {
    private func withoutFirstFund(_ snapshot: DatasetSnapshot) -> DatasetSnapshot {
        var trimmed = snapshot
        trimmed.series.removeFirst()
        return trimmed
    }

    @Test func productsThisVersionCannotOfferAreLeftOutAndCounted() throws {
        let mutations: [(inout FundDescriptor) -> Void] = [
            { $0.currency = "USD" }, { $0.valueBasis = "price" }, { $0.valueBasis = "nav" },
            { $0.path = "https://evil.example/data.json" }, { $0.path = "../test.json" },
            { $0.path = "funds/%2e%2e/test.json" }, { $0.id = "../private" },
            { $0.shortName = "" }, { $0.shortName = String(repeating: "長", count: 21) + "サンプル" },
            { $0.summary = "  " }, { $0.summary = String(repeating: "長", count: 61) }, { $0.category = "" },
            { $0.displayName = "オルカン" }, { $0.shortName = "オルカン" },
            { $0.firstDate = "2025-02-30" }, { $0.firstDate = "2026-09-05" },
        ]
        for mutate in mutations {
            var snapshot = Fixtures.snapshot()
            mutate(&snapshot.manifest.funds[0])
            let offered = try DatasetValidator.validateManifest(snapshot.manifest, mode: .sample)
            #expect(offered.map(\.id) == Array(Fixtures.ids().dropFirst()))
            let dataset = try Fixtures.validated(withoutFirstFund(snapshot))
            #expect(dataset.funds.count == Fixtures.ids().count - 1)
            #expect(dataset.hiddenFundCount == 1)
            #expect(dataset.defaultSelection == Array(Fixtures.ids()[1...2]))
        }
    }

    @Test func liveProductsThatLookLikeSamplesAreLeftOut() throws {
        let mutations: [(inout FundDescriptor) -> Void] = [
            { $0.displayName += "（サンプル）" }, { $0.shortName += "（サンプル）" }, { $0.valueBasis = "reinvestedIndex" },
        ]
        for mutate in mutations {
            var snapshot = Fixtures.snapshot(mode: .live)
            mutate(&snapshot.manifest.funds[0])
            let dataset = try DatasetValidator.validate(withoutFirstFund(snapshot), mode: .live)
            #expect(!dataset.funds.contains { $0.descriptor.id == "all-country" })
            #expect(dataset.hiddenFundCount == 1)
        }
    }

    @Test func aProductThisVersionCannotReadIsLeftOutWithoutLosingTheCatalog() throws {
        let snapshot = Fixtures.snapshot()
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.manifest)) as? [String: Any])
        var funds = try #require(object["funds"] as? [[String: Any]])
        funds[0].removeValue(forKey: "shortName")
        funds[1]["firstDate"] = 20_241_230
        object["funds"] = funds
        object["notices"] = ["登録商標の表記", 42]
        let manifest = try JSONDecoder().decode(Manifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(manifest.funds.map(\.id) == Array(Fixtures.ids().dropFirst(2)))
        #expect(manifest.notices == ["登録商標の表記"])
        object.removeValue(forKey: "notices")
        let silent = try JSONDecoder().decode(Manifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(silent.notices.isEmpty)
    }

    @Test func aCatalogWithNothingThisVersionCanOfferIsRejected() {
        var snapshot = Fixtures.snapshot()
        for index in snapshot.manifest.funds.indices { snapshot.manifest.funds[index].valueBasis = "price" }
        #expect(throws: DataIssue.self) { try DatasetValidator.validateManifest(snapshot.manifest, mode: .sample) }
    }

    @Test func productsComeAndGoWithTheCatalog() throws {
        var snapshot = Fixtures.snapshot()
        var added = snapshot.manifest.funds[0]
        added.id = "demo-new-fund"
        added.displayName = "新しい商品（サンプル）"
        added.shortName = "新商品（サンプル）"
        added.summary = "あとから配信した商品"
        added.path = "funds/demo-new-fund.sample-v1.json"
        snapshot.manifest.funds.append(added)
        var series = snapshot.series[0]
        series.fundId = added.id
        snapshot.series.append(series)
        let dataset = try Fixtures.validated(snapshot)
        let offered = try #require(dataset.funds.last?.descriptor)
        #expect(offered.shortName == "新商品（サンプル）")
        #expect(offered.summary == "あとから配信した商品")
        #expect(dataset.hiddenFundCount == 0)

        let name = "tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = ComparisonModel(defaults: defaults)
        model.toggle("demo-new-fund", in: dataset)
        model.toggle("demo-all-country", in: dataset)
        model.toggle("demo-sp500", in: dataset)
        #expect(model.selectedIDs(in: dataset) == ["demo-new-fund"])
        // A product the catalog no longer lists drops out of the saved selection.
        var withdrawn = snapshot
        withdrawn.manifest.funds.removeLast()
        withdrawn.series.removeLast()
        #expect(model.selectedIDs(in: try Fixtures.validated(withdrawn)) == ["demo-all-country", "demo-sp500"])
    }

    @Test func noticesAndSourcesComeFromTheCatalog() throws {
        var snapshot = Fixtures.snapshot()
        let trademark = "「オルカン」は三菱UFJアセットマネジメントの登録商標です。"
        snapshot.manifest.notices = [trademark, "", String(repeating: "長", count: 201)]
            + (1...12).map { "表記\($0)" }
        snapshot.series[1].source.name = "別の運用会社"
        snapshot.series[2].source.name = "別の運用会社"
        let dataset = try Fixtures.validated(snapshot)
        #expect(dataset.notices == [trademark] + (1...9).map { "表記\($0)" })
        #expect(dataset.sourceNames == ["テスト専用の架空値", "別の運用会社"])
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06", fundIDs: ["demo-sp500", "demo-topix"]),
            dataset: dataset)
        #expect(result.sourceNames == ["別の運用会社"])
    }

    @Test func groupsFollowFirstAppearanceAndStayFlatWithoutCategories() throws {
        let funds = Fixtures.snapshot().manifest.funds
        let flat = FundGroup.grouping(funds)
        #expect(flat.count == 1)
        #expect(flat[0].title == nil)
        #expect(flat[0].funds.map(\.id) == Fixtures.ids())

        var grouped = Array(funds.prefix(5))
        grouped[0].category = "株式"
        grouped[1].category = "債券"
        grouped[2].category = "株式"
        grouped[4].category = "金"
        let groups = FundGroup.grouping(grouped)
        #expect(groups.map(\.title) == ["株式", "債券", "その他", "金"])
        #expect(groups.map { $0.funds.map(\.id) } == [
            ["demo-all-country", "demo-topix"], ["demo-sp500"], ["demo-nasdaq100"], ["demo-nikkei225"],
        ])
    }
}
