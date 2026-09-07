import Foundation
import Testing

@testable import TararebaToushi

@MainActor struct LiveDataTests {
    @Test func ordinaryNAVCalculatesHoldingsWithoutAddingCashDistributions() throws {
        let snapshot = Fixtures.snapshot(a: "9000", mode: .live)
        let dataset = try DatasetValidator.validate(snapshot, mode: .live)
        let result = try SimulationCalculator.calculate(
            .init(amount: 1_000_000, requestedDate: "2025-01-06"), dataset: dataset)
        // A drop in NAV is a drop in holdings value. No assumed distribution is added.
        #expect(result.funds[0].displayedValuation == 900_000)
        #expect(result.funds[0].displayedProfit == -100_000)
        #expect(result.funds[0].returnPercent == -10)
    }

    @Test func unverifiedReinvestedDataCannotBeTreatedAsOrdinaryNAV() {
        for version in ["live-reinvested", "mufg-20260904-6c4cf880560d"] {
            var snapshot = Fixtures.snapshot(version: version, mode: .live)
            snapshot.series[0].valueBasis = "reinvestedIndex"
            #expect(throws: DataIssue.self) { try DatasetValidator.validate(snapshot, mode: .live) }
        }
    }

    @Test func defaultUsesLiveAndCacheIdentityIsSeparate() {
        let live = AppConfiguration()
        let sample = AppConfiguration(mode: .sample)
        #expect(live.mode == .live)
        #expect(live.manifestURL?.path == "/live/manifest.json")
        #expect(sample.manifestURL?.path == "/sample/manifest.json")
        #expect(live.cacheIdentity != sample.cacheIdentity)
    }

    @Test func appContainsNoBundledHistory() {
        #expect(Bundle.main.url(forResource: "BundledLive", withExtension: "json") == nil)
        #expect(Bundle.main.url(forResource: "BundledSample", withExtension: "json") == nil)
        #expect((Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []).isEmpty)
        #expect((Bundle.main.urls(forResourcesWithExtension: "csv", subdirectory: nil) ?? []).isEmpty)
    }

    @Test func firstLaunchFailureShowsNoResultsAndRetryDownloadsData() async throws {
        let transport = MockTransport()
        let store = MemoryStore()
        let repo = FundRepository(configuration: AppConfiguration(), transport: transport, store: store)
        await repo.start()
        #expect(repo.dataset == nil)
        #expect(await store.value == nil)
        #expect(repo.statusLabel == "データ未取得")
        #expect(repo.message?.contains("404") == true)
        #expect(repo.checkedAt == nil && repo.fetchedAt == nil)
        #expect(!repo.isLoading && !repo.isRefreshing)
        let updated = Fixtures.snapshot(version: "live-v2", mode: .live)
        await transport.set(try Fixtures.responses(updated))
        await repo.refresh(force: true)
        #expect(repo.dataset?.snapshot == updated)
        #expect(repo.statusLabel == "取得済みの実データを表示中")
        #expect(repo.fetchedAt != nil)
    }

    @Test func liveRefreshRejectsSampleAndKeepsPreviousSnapshot() async throws {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        let response = try JSONEncoder().encode(Fixtures.snapshot().manifest)
        let repo = FundRepository(
            configuration: AppConfiguration(), transport: MockTransport(["/live/manifest.json": response]),
            store: MemoryStore(Fixtures.envelope(snapshot)))
        await repo.start()
        #expect(repo.dataset?.snapshot == snapshot)
        #expect(repo.checkedAt == nil)
        #expect(repo.message != nil)
    }

    @Test func firstLaunchDownloadsBothHistoriesBeforeShowingResults() async throws {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        let transport = MockTransport(try Fixtures.responses(snapshot))
        let store = MemoryStore()
        let repo = FundRepository(configuration: AppConfiguration(), transport: transport, store: store)
        #expect(repo.dataset == nil)
        await repo.start()
        #expect(await transport.count == 3)
        #expect(repo.dataset?.snapshot == snapshot)
        #expect(await store.value?.snapshot == snapshot)
        #expect(repo.fetchedAt != nil)
        let dataset = try #require(repo.dataset)
        let result = try SimulationCalculator.calculate(.init(amount: 1_000_000, requestedDate: "2025-01-01"), dataset: dataset)
        #expect(!result.isSample)
        #expect(result.funds[0].displayedValuation == 1_200_000)
    }

    @Test func partialFirstDownloadDoesNotLeavePartialCache() async throws {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        var responses = try Fixtures.responses(snapshot)
        responses.removeValue(forKey: "/live/funds/sp500.live-v1.json")
        let store = MemoryStore()
        let repo = FundRepository(configuration: AppConfiguration(), transport: MockTransport(responses), store: store)
        await repo.start()
        #expect(repo.dataset == nil)
        #expect(await store.value == nil)
        #expect(repo.checkedAt == nil)
    }

    @Test func downloadedDataIsAvailableOnLaterOfflineLaunch() async {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        let repo = FundRepository(
            configuration: AppConfiguration(), transport: MockTransport(), store: MemoryStore(Fixtures.envelope(snapshot)))
        await repo.start()
        #expect(repo.dataset?.snapshot == snapshot)
        #expect(repo.message?.contains("404") == true)
        #expect(repo.statusLabel == "取得済みの実データを表示中")
    }

    @Test func oldBundledCacheMustBeDownloadedAgain() async throws {
        let snapshot = Fixtures.snapshot(version: "live-v1", mode: .live)
        var legacy = Fixtures.envelope(snapshot, checkedAt: Date())
        legacy.origin = .bundled
        legacy.fetchedAt = nil
        let store = MemoryStore(legacy)
        let transport = MockTransport(try Fixtures.responses(snapshot))
        let repo = FundRepository(configuration: AppConfiguration(), transport: transport, store: store)
        await repo.start(refresh: false)
        #expect(repo.dataset == nil)
        #expect(repo.checkedAt == nil)
        await repo.refresh()
        #expect(await transport.count == 3)
        #expect(await store.value?.origin == .remote)
        #expect(await store.value?.fetchedAt != nil)
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
