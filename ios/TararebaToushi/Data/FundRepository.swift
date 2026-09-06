import Foundation
import Observation

@MainActor @Observable
final class FundRepository {
    private(set) var dataset: ValidatedDataset?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var message: String?
    private(set) var origin: SnapshotOrigin = .bundled
    private(set) var fetchedAt: Date?
    private(set) var checkedAt: Date?
    let configuration: AppConfiguration
    @ObservationIgnored private let remote: RemoteDataSource
    @ObservationIgnored private let store: any SnapshotStore
    @ObservationIgnored private let bundled: @Sendable () async throws -> ValidatedDataset
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var started = false

    init(
        configuration: AppConfiguration, transport: any JSONTransport,
        store: any SnapshotStore, bundled: @escaping @Sendable () async throws -> ValidatedDataset,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.remote = RemoteDataSource(configuration: configuration, transport: transport)
        self.store = store
        self.bundled = bundled
        self.now = now
    }

    static func makeDefault() -> FundRepository {
        var configuration = AppConfiguration()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--offline-sample") {
                configuration.mode = .sample
            }
        #endif
        let directory = URL.applicationSupportDirectory.appendingPathComponent("FundSnapshots", isDirectory: true)
        let source = BundledDatasetSource(mode: configuration.mode)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let testDirectory = URL.temporaryDirectory.appendingPathComponent(
                    "UITestSnapshots-\(UUID().uuidString)")
                return FundRepository(
                    configuration: configuration, transport: UITestOfflineTransport(),
                    store: LocalSnapshotStore(directory: testDirectory, configuration: configuration),
                    bundled: { try await source.load() })
            }
        #endif
        return FundRepository(
            configuration: configuration, transport: URLSessionTransport(),
            store: LocalSnapshotStore(directory: directory, configuration: configuration),
            bundled: { try await source.load() })
    }

    var statusLabel: String {
        guard dataset != nil else { return "データ未取得" }
        let kind = configuration.mode == .sample ? "サンプル" : "実データ"
        if origin == .bundled { return "同梱\(kind)を表示中" }
        return "取得済みの\(kind)を表示中"
    }

    var isStale: Bool {
        guard let checkedAt else { return true }
        return now().timeIntervalSince(checkedAt) >= configuration.refreshInterval
    }

    func start(refresh: Bool = true) async {
        guard !started else { return }
        started = true
        isLoading = true
        do {
            if let cached = try await store.load() {
                let mode = configuration.mode
                dataset =
                    try await Task.detached {
                        try DatasetValidator.validate(cached.snapshot, mode: mode)
                    }
                    .value
                origin = cached.origin
                fetchedAt = cached.fetchedAt
                checkedAt = cached.checkedAt
            }
        } catch {
            message = "保存データを読み込めませんでした。利用できるデータを確認します。"
        }
        if dataset == nil {
            do {
                let candidate = try await bundled()
                guard candidate.snapshot.manifest.isSample == (configuration.mode == .sample) else {
                    throw DataIssue("同梱データのモードが一致しません。")
                }
                dataset = candidate
            } catch { message = error.localizedDescription }
        }
        isLoading = false
        if refresh { await self.refresh() }
    }

    func refresh(force: Bool = false) async {
        guard started, !isLoading, !isRefreshing else { return }
        if !force, let checkedAt {
            let age = now().timeIntervalSince(checkedAt)
            if age >= 0, age < configuration.refreshInterval { return }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let manifest = try await remote.manifest()
            let candidate: ValidatedDataset
            let newOrigin: SnapshotOrigin
            let newFetchedAt: Date?
            if let current = dataset, manifest.datasetVersion == current.snapshot.manifest.datasetVersion {
                guard manifest == current.snapshot.manifest else {
                    throw DataIssue("同じ版のデータ一覧が変更されています。以前のデータを保持します。")
                }
                candidate = current
                newOrigin = origin
                newFetchedAt = fetchedAt
            } else {
                candidate = try await remote.dataset(manifest: manifest)
                newOrigin = .remote
                newFetchedAt = now()
            }
            let checked = now()
            let envelope = StoredSnapshot(
                identity: configuration.cacheIdentity, snapshot: candidate.snapshot,
                origin: newOrigin, fetchedAt: newFetchedAt, checkedAt: checked)
            try await store.save(envelope)
            dataset = candidate
            origin = newOrigin
            fetchedAt = newFetchedAt
            checkedAt = checked
            message = nil
        } catch is CancellationError {
            message = "更新を中断しました。もう一度お試しください。"
        } catch {
            message = error.localizedDescription
        }
    }
}

#if DEBUG
    nonisolated private struct UITestOfflineTransport: JSONTransport {
        func fetch(_ url: URL) async throws -> Data {
            throw DataIssue("配信ファイルがまだ配置されていません（404）。保存済みのデータで引き続き比較できます。")
        }
    }
#endif
