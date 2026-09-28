import Foundation

// Which products exist is the catalog's to say; the mode only picks the catalog.
nonisolated enum DatasetMode: String, Codable, Sendable {
    case sample, live

    var label: String { self == .sample ? "サンプル" : "実データ" }
}

nonisolated struct AppConfiguration: Sendable {
    var dataBaseURL = "https://tarareba-data.hibiki-apps.workers.dev/"
    var mode: DatasetMode = .live
    var manifestPath: String { "\(mode.rawValue)/manifest.json" }
    var refreshInterval: TimeInterval = 6 * 60 * 60
    static let schemaVersion = 2
    // Raised when a saved snapshot can no longer be read, so it is fetched again instead.
    static let snapshotStorageVersion = 2
    static let maximumAmount = 1_000_000_000
    // A comparison stays legible while the series stay visually distinct.
    static let maximumComparisonFunds = 8
    static let defaultComparisonFunds = 2
    static let initialAmount = 1_000_000
    static let initialMonthlyAmount = 30_000
    static let initialDate = "2025-01-01"
    static let maximumResponseBytes = 2 * 1024 * 1024
    // Every offered product's history is downloaded, so the catalog this version uses is
    // bounded. Products past it stay hidden; a larger catalog needs its own URL.
    static let maximumCatalogFunds = 20
    static let maximumStoredBytes = maximumCatalogFunds * maximumResponseBytes + maximumResponseBytes
    static let maximumNotices = 10

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
