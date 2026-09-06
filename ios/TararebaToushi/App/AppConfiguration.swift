import Foundation

nonisolated enum DatasetMode: String, Codable, Sendable {
    case sample, live

    var fundIDs: [String] {
        switch self {
        case .sample: ["demo-all-country", "demo-sp500"]
        case .live: ["all-country", "sp500"]
        }
    }
}

nonisolated struct AppConfiguration: Sendable {
    var dataBaseURL = "https://tarareba-data.hibiki-apps.workers.dev/"
    var manifestPath = "sample/manifest.json"
    var mode: DatasetMode = .sample
    var refreshInterval: TimeInterval = 6 * 60 * 60
    static let schemaVersion = 1
    static let maximumAmount = 1_000_000_000
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
        "\(manifestURL?.absoluteString ?? dataBaseURL)|\(mode.rawValue)|schema-\(Self.schemaVersion)"
    }
}
