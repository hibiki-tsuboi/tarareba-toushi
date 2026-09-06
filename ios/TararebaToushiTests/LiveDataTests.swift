import Foundation
import Testing

@testable import TararebaToushi

@MainActor struct LiveDataTests {
    @Test func defaultUsesLiveAndCacheIdentityIsSeparate() {
        let live = AppConfiguration()
        let sample = AppConfiguration(mode: .sample)
        #expect(live.mode == .live)
        #expect(live.manifestURL?.path == "/live/manifest.json")
        #expect(sample.manifestURL?.path == "/sample/manifest.json")
        #expect(live.cacheIdentity != sample.cacheIdentity)
    }

    @Test func bundledOfficialDataIsValidAndUsableOffline() async throws {
        let source = BundledDatasetSource(mode: .live)
        let dataset = try await source.load()
        #expect(!dataset.snapshot.manifest.isSample)
        #expect(dataset.earliestRequestedDate.rawValue == "2018-10-31")
        #expect(dataset.funds.allSatisfy { $0.series.source.kind == "official" })
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-01"), dataset: dataset)
        #expect(!result.isSample)
        #expect(result.funds.allSatisfy { $0.points.first?.amount == 1_000_000 })
        #expect(result.startDate.rawValue == "2025-01-06")
    }

    @Test func liveBundleSurvivesRemote404AndCanUpdateLater() async throws {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        let bundle = try DatasetValidator.validate(snapshot, mode: .live)
        let transport = MockTransport()
        let repo = FundRepository(
            configuration: AppConfiguration(), transport: transport, store: MemoryStore(), bundled: { bundle })
        await repo.start()
        #expect(repo.dataset?.snapshot == snapshot)
        #expect(repo.statusLabel == "同梱実データを表示中")
        #expect(repo.message?.contains("404") == true)
        let updated = Fixtures.snapshot(version: "live-v2", mode: .live)
        await transport.set(try Fixtures.responses(updated))
        await repo.refresh(force: true)
        #expect(repo.dataset?.snapshot == updated)
        #expect(repo.statusLabel == "取得済みの実データを表示中")
        #expect(repo.fetchedAt != nil)
    }

    @Test func liveRefreshRejectsSampleAndKeepsPreviousSnapshot() async throws {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        let bundle = try DatasetValidator.validate(snapshot, mode: .live)
        let response = try JSONEncoder().encode(Fixtures.snapshot().manifest)
        let repo = FundRepository(
            configuration: AppConfiguration(), transport: MockTransport(["/live/manifest.json": response]),
            store: MemoryStore(), bundled: { bundle })
        await repo.start()
        #expect(repo.dataset?.snapshot == snapshot)
        #expect(repo.checkedAt == nil)
        #expect(repo.message != nil)
    }

    @Test func liveValidationRejectsSyntheticSourceAndInvalidAttribution() {
        let mutations: [(inout DatasetSnapshot) -> Void] = [
            { $0.series[0].source.kind = "synthetic" }, { $0.series[0].source.url = nil },
            { $0.series[0].source.url = "http://example.com/" },
            { $0.series[0].source.url = "https://user:password@example.com/" },
            { $0.manifest.funds[0].displayName += "（サンプル）" },
        ]
        for mutate in mutations {
            var snapshot = Fixtures.snapshot(mode: .live)
            mutate(&snapshot)
            #expect(throws: DataIssue.self) { try DatasetValidator.validate(snapshot, mode: .live) }
        }
    }
}
