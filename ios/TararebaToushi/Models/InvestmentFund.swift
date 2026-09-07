import Foundation

nonisolated enum InvestmentFund: String, CaseIterable, Codable, Identifiable, Sendable {
    case allCountry = "all-country"
    case sp500 = "sp500"
    case topix = "topix"
    case nasdaq100 = "nasdaq100"
    case nikkei225 = "nikkei225"
    case gold = "gold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allCountry: "オルカン"
        case .sp500: "S&P500"
        case .topix: "TOPIX"
        case .nasdaq100: "NASDAQ100"
        case .nikkei225: "日経平均"
        case .gold: "純金"
        }
    }

    func dataID(isSample: Bool) -> String {
        isSample ? "demo-\(rawValue)" : rawValue
    }
}

extension FundDescriptor {
    // Known funds get a short label; anything delivered later falls back to its name.
    var shortName: String {
        let fund = InvestmentFund.allCases.first {
            id == $0.dataID(isSample: false) || id == $0.dataID(isSample: true)
        }
        guard let fund else { return displayName }
        return fund.displayName + (id.hasPrefix("demo-") ? "（サンプル）" : "")
    }
}
