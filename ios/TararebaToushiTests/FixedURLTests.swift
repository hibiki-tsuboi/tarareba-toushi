import CryptoKit
import Foundation
import Testing

@testable import TararebaToushi

nonisolated enum FixedFixtures {
    static func snapshot(version: String = "catalog-v1", a: String = "12000", b: String = "14000") throws -> DatasetSnapshot {
        var snapshot = Fixtures.snapshot(version: version, a: a, b: b, mode: .live)
        snapshot.manifest.schemaVersion = 2
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for index in snapshot.series.indices {
            snapshot.series[index].schemaVersion = 2
            snapshot.series[index].datasetVersion = ""
            let hash = SHA256.hash(data: try encoder.encode(snapshot.series[index])).map { String(format: "%02x", $0) }.joined()
            snapshot.series[index].datasetVersion = "fund-\(hash)"
            snapshot.manifest.funds[index].contentVersion = snapshot.series[index].datasetVersion
            snapshot.manifest.funds[index].path = "funds/\(snapshot.series[index].fundId).json"
        }
        return snapshot
    }
}

@MainActor struct FixedURLTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func repository(_ transport: any JSONTransport, _ store: any SnapshotStore = MemoryStore()) -> FundRepository {
        let date = now
        return FundRepository(configuration: AppConfiguration(), transport: transport, store: store, now: { date })
    }

    @Test func downloadsFixedPathsAndUnchangedRefreshOnlyChecksCatalog() async throws {
        let snapshot = try FixedFixtures.snapshot()
        let transport = MockTransport(try Fixtures.responses(snapshot))
        let repo = repository(transport)
        await repo.start()
        #expect(repo.dataset?.snapshot == snapshot)
        let live = Fixtures.ids(.live)
        #expect(await transport.requests.map(\.path)
            == ["/live/manifest.json"] + live.map { "/live/funds/\($0).json" })
        // An unchanged catalog costs one request; nothing is downloaded again.
        await repo.refresh(force: true)
        #expect(await transport.count == live.count + 2)
        await repo.refresh()
        #expect(await transport.count == live.count + 2)
    }

    @Test func correctionOnSameDateDownloadsOnlyChangedFundAndKeepsOtherSeries() async throws {
        let old = try FixedFixtures.snapshot()
        let next = try FixedFixtures.snapshot(version: "catalog-v2", a: "11000")
        let transport = MockTransport(try Fixtures.responses(next))
        let store = MemoryStore(Fixtures.envelope(old))
        let repo = repository(transport, store)
        await repo.start()
        #expect(repo.dataset?.snapshot == next)
        #expect(await store.value?.snapshot == next)
        #expect(await transport.requests.map(\.path) == ["/live/manifest.json", "/live/funds/all-country.json"])
        #expect(repo.fetchedAt == now)
    }

    @Test func hundredFundCatalogDownloadsOnlyTheProductsThisVersionOffers() async throws {
        var snapshot = try FixedFixtures.snapshot()
        for index in snapshot.manifest.funds.count..<100 {
            var fund = snapshot.manifest.funds[0]
            fund.id = "additional-\(index)"
            fund.displayName = "追加商品\(index)"
            fund.shortName = "追加\(index)"
            fund.path = "funds/\(fund.id).json"
            snapshot.manifest.funds.append(fund)
            var series = snapshot.series[0]
            series.fundId = fund.id
            snapshot.series.append(series)
        }
        let transport = MockTransport(try Fixtures.responses(snapshot))
        let repo = repository(transport)
        await repo.start()
        let offered = AppConfiguration.maximumCatalogFunds
        #expect(repo.dataset?.snapshot.manifest.funds.count == 100)
        #expect(repo.dataset?.funds.map(\.descriptor.id) == snapshot.manifest.funds.prefix(offered).map(\.id))
        #expect(repo.dataset?.hiddenFundCount == 100 - offered)
        #expect(await transport.count == offered + 1)
        // A change to a product past the limit downloads nothing.
        let fetchedAt = repo.fetchedAt
        snapshot.manifest.datasetVersion = "catalog-v2"
        snapshot.manifest.funds[99].contentVersion = "fund-" + String(repeating: "f", count: 64)
        await transport.set(try Fixtures.responses(snapshot))
        await repo.refresh(force: true)
        #expect(await transport.count == offered + 2)
        #expect(repo.dataset?.snapshot.manifest == snapshot.manifest)
        #expect(repo.fetchedAt == fetchedAt)
    }

    @Test func aKindOfProductThisVersionCannotComputeIsNeverDownloaded() async throws {
        var snapshot = try FixedFixtures.snapshot()
        snapshot.manifest.funds[2].valueBasis = "price"
        snapshot.series[2].valueBasis = "price"
        let transport = MockTransport(try Fixtures.responses(snapshot))
        let repo = repository(transport)
        await repo.start()
        #expect(repo.dataset?.hiddenFundCount == 1)
        #expect(repo.dataset?.funds.contains { $0.descriptor.id == "topix" } == false)
        #expect(await transport.requests.map(\.path).contains("/live/funds/topix.json") == false)
        #expect(await transport.count == Fixtures.ids(.live).count)
    }

    @Test func staleHistoryAtFixedURLRetriesAndNeverReplacesValidCache() async throws {
        let old = try FixedFixtures.snapshot()
        var next = try FixedFixtures.snapshot(version: "catalog-v2", a: "11000")
        next.series[0] = old.series[0]
        let transport = MockTransport(try Fixtures.responses(next))
        let store = MemoryStore(Fixtures.envelope(old))
        let repo = repository(transport, store)
        await repo.start()
        #expect(await transport.count == 4)
        #expect(repo.dataset?.snapshot == old)
        #expect(await store.value?.snapshot == old)
        #expect(repo.checkedAt == nil)
        #expect(repo.message?.contains("切り替わっています") == true)
        let corrected = try FixedFixtures.snapshot(version: "catalog-v2", a: "11000")
        await transport.set(try Fixtures.responses(corrected))
        await repo.refresh(force: true)
        #expect(repo.dataset?.snapshot == corrected)
    }

    @Test func deploymentBetweenCatalogAndHistoryRequestsRecoversAutomatically() async throws {
        let old = try FixedFixtures.snapshot()
        let next = try FixedFixtures.snapshot(version: "catalog-v2", a: "11000", b: "13000")
        let transport = SwitchingCatalogTransport(first: try JSONEncoder().encode(old.manifest), responses: try Fixtures.responses(next))
        let repo = repository(transport)
        await repo.start()
        #expect(repo.dataset?.snapshot == next)
        #expect(repo.message == nil)
        #expect(await transport.catalogRequests == 2)
    }

    @Test func partialOrDiskFailureKeepsPreviousSnapshot() async throws {
        let old = try FixedFixtures.snapshot()
        let next = try FixedFixtures.snapshot(version: "catalog-v2", a: "11000", b: "13000")
        for failSave in [false, true] {
            var responses = try Fixtures.responses(next)
            if !failSave { responses.removeValue(forKey: "/live/funds/sp500.json") }
            let store = MemoryStore(Fixtures.envelope(old), failSave: failSave)
            let repo = repository(MockTransport(responses), store)
            await repo.start()
            #expect(repo.dataset?.snapshot == old)
            #expect(await store.value?.snapshot == old)
            #expect(repo.checkedAt == nil)
            #expect(repo.message != nil)
        }
    }

    @Test func legacyDiskCacheSurvivesOfflineAndMigratesToFixedURLs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = AppConfiguration()
        #expect(config.cacheIdentity.hasSuffix("|schema-2"))
        let store = LocalSnapshotStore(directory: directory, configuration: config)
        let legacy = Fixtures.snapshot(version: "legacy-live", mode: .live)
        try await store.save(Fixtures.envelope(legacy))
        let transport = MockTransport()
        let repo = repository(transport, store)
        await repo.start()
        #expect(repo.dataset?.snapshot == legacy)
        let next = try FixedFixtures.snapshot()
        await transport.set(try Fixtures.responses(next))
        await repo.refresh(force: true)
        #expect(repo.dataset?.snapshot == next)
        #expect(try await store.load()?.snapshot == next)
        let offline = repository(MockTransport(), store)
        await offline.start()
        #expect(offline.dataset?.snapshot == next)
    }

    @Test func anUnknownFormatIsRejectedBeforeAnyHistoryRequest() async throws {
        var snapshot = try FixedFixtures.snapshot()
        snapshot.manifest.schemaVersion = 3
        let transport = MockTransport(try Fixtures.responses(snapshot))
        let repo = repository(transport)
        await repo.start()
        #expect(await transport.count == 1)
        #expect(repo.dataset == nil)
        #expect(repo.message != nil)
    }

    @Test func missingOrUnsafeContentInformationLeavesOnlyThatProductOut() async throws {
        let mutations: [(inout DatasetSnapshot) -> Void] = [
            { $0.manifest.funds[0].contentVersion = nil },
            { $0.manifest.funds[0].contentVersion = "invalid" },
            { $0.manifest.funds[0].path = "funds/all-country.old.json" },
            { $0.manifest.funds[0].id = "../private" },
        ]
        for mutate in mutations {
            var snapshot = try FixedFixtures.snapshot()
            mutate(&snapshot)
            let transport = MockTransport(try Fixtures.responses(snapshot))
            let repo = repository(transport)
            await repo.start()
            // Its path is never requested; the others load as usual.
            #expect(await transport.requests.map(\.path).contains { $0.contains("all-country") || $0.contains("private") } == false)
            #expect(await transport.count == Fixtures.ids(.live).count)
            #expect(repo.dataset?.funds.first?.descriptor.id == "sp500")
            #expect(repo.dataset?.hiddenFundCount == 1)
        }
    }
}

private actor SwitchingCatalogTransport: JSONTransport {
    let first: Data
    let responses: [String: Data]
    var catalogRequests = 0

    init(first: Data, responses: [String: Data]) {
        self.first = first
        self.responses = responses
    }

    func fetch(_ url: URL) throws -> Data {
        if url.path == "/live/manifest.json" {
            catalogRequests += 1
            if catalogRequests == 1 { return first }
        }
        guard let data = responses[url.path] else { throw DataIssue("404") }
        return data
    }
}
