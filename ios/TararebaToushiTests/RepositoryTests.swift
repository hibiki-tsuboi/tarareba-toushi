import Foundation
import Testing

@testable import TararebaToushi

@MainActor struct RepositoryTests {
    private func repository(
        transport: MockTransport = MockTransport(), store: any SnapshotStore = MemoryStore(),
        configuration: AppConfiguration = AppConfiguration(mode: .sample), now: Date = Date(timeIntervalSince1970: 10_000)
    ) -> FundRepository {
        FundRepository(
            configuration: configuration, transport: transport, store: store,
            bundled: { try Fixtures.validated() }, now: { now })
    }

    @Test func offlineFirstLaunchAnd404() async {
        let repo = repository()
        await repo.start()
        #expect(repo.dataset != nil)
        #expect(repo.origin == .bundled)
        #expect(repo.message?.contains("404") == true)
        #expect(repo.checkedAt == nil)
        #expect(!repo.isRefreshing)
    }

    @Test func corruptCacheFallsBackToBundle() async {
        let repo = repository(store: MemoryStore(corrupt: true))
        await repo.start(refresh: false)
        #expect(repo.dataset != nil)
        #expect(repo.origin == .bundled)
        #expect(repo.message != nil)
    }

    @Test func liveModeNeverFallsBackToSample() async {
        var config = AppConfiguration()
        config.mode = .live
        let repo = repository(configuration: config)
        await repo.start(refresh: false)
        #expect(repo.dataset == nil)
    }

    @Test func unchangedVersionOnlyFetchesManifestAndThrottles() async throws {
        let transport = MockTransport(try Fixtures.responses(Fixtures.snapshot()))
        let repo = repository(transport: transport)
        await repo.start()
        #expect(await transport.count == 1)
        #expect(repo.checkedAt != nil)
        #expect(repo.fetchedAt == nil)
        await repo.refresh()
        #expect(await transport.count == 1)
        await repo.refresh(force: true)
        #expect(await transport.count == 2)
    }

    @Test func newVersionIsSavedAndSwappedTogether() async throws {
        let transport = MockTransport(try Fixtures.responses(Fixtures.snapshot(version: "sample-v2", b: "8000")))
        let store = MemoryStore(Fixtures.envelope())
        let repo = repository(transport: transport, store: store)
        await repo.start()
        #expect(repo.dataset?.snapshot.manifest.datasetVersion == "sample-v2")
        #expect(repo.dataset?.snapshot.series.allSatisfy { $0.datasetVersion == "sample-v2" } == true)
        #expect(await store.value?.snapshot.manifest.datasetVersion == "sample-v2")
        #expect(repo.origin == .remote)
        #expect(repo.fetchedAt == Date(timeIntervalSince1970: 10_000))
        #expect(await transport.count == 3)
    }

    @Test(arguments: ["missing", "json", "mode", "version"])
    func partialOrInvalidNewVersionKeepsOld(kind: String) async throws {
        var updated = Fixtures.snapshot(version: "sample-v2")
        if kind == "mode" { updated.series[1].isSample = false }
        if kind == "version" { updated.series[1].datasetVersion = "sample-v3" }
        var responses = try Fixtures.responses(updated)
        if kind == "missing" { responses.removeValue(forKey: "/sample/funds/demo-sp500.sample-v2.json") }
        if kind == "json" { responses["/sample/funds/demo-sp500.sample-v2.json"] = Data("{broken".utf8) }
        let transport = MockTransport(responses)
        let old = Fixtures.envelope()
        let store = MemoryStore(old)
        let repo = repository(transport: transport, store: store)
        await repo.start()
        #expect(repo.dataset?.snapshot == old.snapshot)
        #expect(await store.value?.snapshot == old.snapshot)
        #expect(repo.checkedAt == nil)
        #expect(repo.message != nil)
        await transport.set(try Fixtures.responses(Fixtures.snapshot(version: "sample-v2")))
        await repo.refresh(force: true)
        #expect(repo.dataset?.snapshot.manifest.datasetVersion == "sample-v2")
    }

    @Test func diskFailureKeepsOldAndRetryRemainsPossible() async throws {
        let transport = MockTransport(try Fixtures.responses(Fixtures.snapshot(version: "sample-v2")))
        let repo = repository(transport: transport, store: MemoryStore(Fixtures.envelope(), failSave: true))
        await repo.start()
        #expect(repo.dataset?.snapshot.manifest.datasetVersion == "sample-v1")
        #expect(repo.checkedAt == nil)
        #expect(repo.message == "保存失敗")
        #expect(!repo.isRefreshing)
    }

    @Test func refreshIsNotDuplicated() async throws {
        let transport = MockTransport(try Fixtures.responses(Fixtures.snapshot()), delay: 50_000_000)
        let repo = repository(transport: transport)
        await repo.start(refresh: false)
        async let first: Void = repo.refresh(force: true)
        async let second: Void = repo.refresh(force: true)
        _ = await (first, second)
        #expect(await transport.count == 1)
    }

    @Test func unsafePathStopsBeforeSeriesRequest() async throws {
        var snapshot = Fixtures.snapshot(version: "sample-v2")
        snapshot.manifest.funds[0].path = "https://evil.example/private.json"
        let transport = MockTransport(["/sample/manifest.json": try JSONEncoder().encode(snapshot.manifest)])
        let repo = repository(transport: transport)
        await repo.start()
        #expect(await transport.count == 1)
        #expect(repo.message != nil)
    }

    @Test func fileStoreRoundTripAndOriginIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = AppConfiguration(mode: .sample)
        let store = LocalSnapshotStore(directory: directory, configuration: config)
        try await store.save(Fixtures.envelope())
        #expect(try await store.load()?.snapshot == Fixtures.snapshot())
        var other = config
        other.dataBaseURL = "https://other.example/"
        let otherStore = LocalSnapshotStore(directory: directory, configuration: other)
        #expect(try await otherStore.load() == nil)
        var broken = Fixtures.envelope()
        broken.snapshot.series[0].isSample = false
        await #expect(throws: DataIssue.self) { try await store.save(broken) }
        #expect(try await store.load()?.snapshot == Fixtures.snapshot())
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let file = try #require(files.first)
        try Data("broken".utf8).write(to: file)
        await #expect(throws: (any Error).self) { try await store.load() }
    }

    @Test func inputChangesAreLocalAndPersistOnlyValidValues() async throws {
        let transport = MockTransport()
        let repo = repository(transport: transport)
        await repo.start(refresh: false)
        let name = "tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = ComparisonModel(defaults: defaults)
        model.recalculate(dataset: repo.dataset)
        #expect(model.result?.input.amount == 1_000_000)
        model.amountText = "2,000,000"
        model.recalculate(dataset: repo.dataset)
        #expect(model.result?.funds[0].valuation == 2_400_000)
        model.amountText = "0"
        model.recalculate(dataset: repo.dataset)
        #expect(model.result == nil)
        #expect(model.inputError != nil)
        #expect(ComparisonModel(defaults: defaults).amountText == "2,000,000")
        #expect(await transport.count == 0)
        #expect(model.preset(years: 5, dataset: repo.dataset) == nil)
        #expect(model.preset(years: 1, dataset: repo.dataset)?.rawValue == "2025-09-04")
    }
}
