import Foundation

nonisolated protocol JSONTransport: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

nonisolated final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

nonisolated struct URLSessionTransport: JSONTransport {
    let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    @concurrent func fetch(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw DataIssue("配信先にはHTTPSのURLを設定してください。")
        }
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw DataIssue("配信先から正しい応答を取得できませんでした。")
        }
        if http.statusCode == 404 {
            throw DataIssue("比較データが見つかりませんでした（404）。時間をおいて再試行してください。")
        }
        guard http.statusCode == 200 else {
            throw DataIssue("データを更新できませんでした（HTTP \(http.statusCode)）。")
        }
        guard http.mimeType == "application/json" else { throw DataIssue("JSON以外の応答を受信しました。") }
        let limit = AppConfiguration.maximumResponseBytes
        guard http.expectedContentLength <= Int64(limit) else { throw DataIssue("配信データのサイズが上限を超えています。") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw DataIssue("配信データのサイズが上限を超えています。") }
            data.append(byte)
        }
        return data
    }
}

nonisolated struct RemoteDataSource: Sendable {
    let configuration: AppConfiguration
    let transport: any JSONTransport

    private func decode<T: Decodable & Sendable>(_ type: T.Type, url: URL) async throws -> T {
        let data = try await transport.fetch(url)
        guard data.count <= AppConfiguration.maximumResponseBytes else { throw DataIssue("データが大きすぎます。") }
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw DataIssue("取得したデータを読み取れませんでした。時間をおいて再試行してください。")
        }
    }

    @concurrent func manifest() async throws -> Manifest {
        guard let url = configuration.manifestURL else { throw DataIssue("配信先の設定が正しくありません。") }
        let manifest = try await decode(Manifest.self, url: url)
        try DatasetValidator.validateManifest(manifest, mode: configuration.mode)
        return manifest
    }

    @concurrent func dataset(manifest: Manifest) async throws -> ValidatedDataset {
        // Validate again at the boundary before using any path from a remote manifest.
        try DatasetValidator.validateManifest(manifest, mode: configuration.mode)
        guard let base = configuration.manifestURL?.deletingLastPathComponent() else {
            throw DataIssue("配信先の設定が正しくありません。")
        }
        var series: [FundSeries] = []
        for fund in manifest.funds {
            series.append(try await decode(FundSeries.self, url: base.appendingPathComponent(fund.path)))
        }
        return try DatasetValidator.validate(
            DatasetSnapshot(manifest: manifest, series: series), mode: configuration.mode)
    }
}
