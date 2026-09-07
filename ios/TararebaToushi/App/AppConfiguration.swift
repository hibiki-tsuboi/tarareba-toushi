import Foundation

nonisolated enum DatasetMode: String, Codable, Sendable {
    case sample, live

    var fundIDs: [String] {
        switch self {
        case .sample:
            ["demo-all-country", "demo-sp500", "demo-topix", "demo-nasdaq100", "demo-nikkei225",
                "demo-gold", "demo-emerging", "demo-nanotech", "demo-genomics", "demo-developed-bond"]
        case .live:
            ["all-country", "sp500", "topix", "nasdaq100", "nikkei225", "gold", "emerging", "nanotech",
                "genomics", "developed-bond"]
        }
    }

    var label: String { self == .sample ? "サンプル" : "実データ" }
}

nonisolated struct AppConfiguration: Sendable {
    var dataBaseURL = "https://tarareba-data.hibiki-apps.workers.dev/"
    var mode: DatasetMode = .live
    var manifestPath: String { "\(mode.rawValue)/manifest.json" }
    var refreshInterval: TimeInterval = 6 * 60 * 60
    static let schemaVersion = 2
    // Preserve existing downloaded snapshots across the wire-format migration.
    static let snapshotStorageVersion = 1
    static let maximumAmount = 1_000_000_000
    // A comparison stays legible while the series stay visually distinct.
    static let maximumComparisonFunds = 8
    static let defaultComparisonFunds = 2
    static let initialAmount = 1_000_000
    static let initialDate = "2025-01-01"
    static let maximumResponseBytes = 2 * 1024 * 1024

    var manifestURL: URL? {
        guard let base = URL(string: dataBaseURL), base.scheme == "https", base.host != nil,
            base.user == nil, base.password == nil,
            manifestPath.range(of: #"^[a-z0-9-]+/manifest\.json$"#, options: .regularExpression) != nil
        else { return nil }
        return base.appendingPathComponent(manifestPath)
    }

    var cacheIdentity: String {
        "\(manifestURL?.absoluteString ?? dataBaseURL)|\(mode.rawValue)|schema-\(Self.snapshotStorageVersion)"
    }
}
