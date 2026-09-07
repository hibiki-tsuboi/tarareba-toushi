import Foundation
import Observation

@MainActor @Observable
final class FundRepository {
    private(set) var dataset: ValidatedDataset?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var message: String?
    private(set) var origin: SnapshotOrigin = .remote
    private(set) var fetchedAt: Date?
    private(set) var checkedAt: Date?
    let configuration: AppConfiguration
    @ObservationIgnored private let remote: RemoteDataSource
    @ObservationIgnored private let store: any SnapshotStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var started = false

    init(
        configuration: AppConfiguration, transport: any JSONTransport,
        store: any SnapshotStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.remote = RemoteDataSource(configuration: configuration, transport: transport)
        self.store = store
        self.now = now
    }

    static func makeDefault() -> FundRepository {
        var configuration = AppConfiguration()
        let directory = URL.applicationSupportDirectory.appendingPathComponent("FundSnapshots", isDirectory: true)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let environment = ProcessInfo.processInfo.environment
                if environment["TARAREBA_TEST_MODE"] == "sample" { configuration.mode = .sample }
                let session = environment["TARAREBA_TEST_SESSION"].flatMap(UUID.init(uuidString:)) ?? UUID()
                let testDirectory = directory.appendingPathComponent("UITests/\(session.uuidString)")
                let transport: any JSONTransport =
                    environment["TARAREBA_TEST_RESPONSES"] != nil || environment["TARAREBA_TEST_OFFLINE"] == "1"
                    ? UITestTransport(environment: environment) : URLSessionTransport()
                return FundRepository(
                    configuration: configuration, transport: transport,
                    store: LocalSnapshotStore(directory: testDirectory, configuration: configuration))
            }
        #endif
        return FundRepository(
            configuration: configuration, transport: URLSessionTransport(),
            store: LocalSnapshotStore(directory: directory, configuration: configuration))
    }

    var statusLabel: String {
        guard dataset != nil else { return "データ未取得" }
        let kind = configuration.mode == .sample ? "サンプル" : "実データ"
        return "取得済みの\(kind)を表示中"
    }

    var isStale: Bool {
        if needsNAVSnapshotUpdate { return true }
        guard let checkedAt else { return true }
        return now().timeIntervalSince(checkedAt) >= configuration.refreshInterval
    }

    private var needsNAVSnapshotUpdate: Bool {
        configuration.mode == .live
            && dataset?.snapshot.series.contains(where: { $0.valueBasis != "nav" }) == true
    }

    func start(refresh: Bool = true) async {
        guard !started else { return }
        started = true
        isLoading = true
        do {
            if let cached = try await store.load(), cached.origin == .remote, cached.fetchedAt != nil {
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
        isLoading = false
        if refresh { await self.refresh() }
    }

    func refresh(force: Bool = false) async {
        guard started, !isLoading, !isRefreshing else { return }
        if !force, !needsNAVSnapshotUpdate, let checkedAt {
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
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                message = "インターネットに接続できません。接続を確認して再試行してください。"
            case .timedOut:
                message = "通信に時間がかかっています。時間をおいて再試行してください。"
            case .cancelled:
                message = "更新を中断しました。もう一度お試しください。"
            default:
                message = "データを取得できませんでした。接続を確認して再試行してください。"
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

#if DEBUG
    // UI tests supply small fictional responses at launch. No history is compiled into the app.
    private actor UITestTransport: JSONTransport {
        private let responses: [String: String]
        private let offline: Bool
        private let failFirst: Bool
        private let failAfter: Int?
        private var requests = 0

        init(environment: [String: String]) {
            let data = Data((environment["TARAREBA_TEST_RESPONSES"] ?? "{}").utf8)
            responses = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            offline = environment["TARAREBA_TEST_OFFLINE"] == "1"
            failFirst = environment["TARAREBA_TEST_FAIL_FIRST"] == "1"
            failAfter = environment["TARAREBA_TEST_FAIL_AFTER"].flatMap(Int.init)
        }

        func fetch(_ url: URL) async throws -> Data {
            requests += 1
            try await Task.sleep(for: .milliseconds(150))
            if offline || (failFirst && requests == 1) { throw URLError(.notConnectedToInternet) }
            if let failAfter, requests > failAfter { throw DataIssue("テスト用の取得失敗（404）。") }
            guard let response = responses[url.path] else { throw DataIssue("テスト用の取得失敗（404）。") }
            return Data(response.utf8)
        }
    }
#endif
