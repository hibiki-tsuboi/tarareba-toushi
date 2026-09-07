import Foundation

nonisolated enum InvestmentFund: String, CaseIterable, Codable, Identifiable, Sendable {
    case allCountry = "all-country"
    case sp500 = "sp500"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allCountry: "オルカン"
        case .sp500: "S&P500"
        }
    }

    func dataID(isSample: Bool) -> String {
        isSample ? "demo-\(rawValue)" : rawValue
    }
}
