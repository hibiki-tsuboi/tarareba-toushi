import Foundation

nonisolated enum InvestmentFund: String, CaseIterable, Codable, Identifiable, Sendable {
    case allCountry = "all-country"
    case sp500 = "sp500"
    case topix = "topix"
    case nasdaq100 = "nasdaq100"
    case nikkei225 = "nikkei225"
    case gold = "gold"
    case emerging = "emerging"
    case nanotech = "nanotech"
    case genomics = "genomics"
    case developedBond = "developed-bond"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allCountry: "オルカン"
        case .sp500: "S&P500"
        case .topix: "TOPIX"
        case .nasdaq100: "NASDAQ100"
        case .nikkei225: "日経平均"
        case .gold: "純金"
        case .emerging: "新興国株"
        case .nanotech: "ナノテク"
        case .genomics: "遺伝子工学"
        case .developedBond: "先進国債券"
        }
    }

    // What the fund holds, in words that need no index name. Kept to what the fund's own
    // classification states: the two Neo funds are 内外, so they are not called American.
    var summary: String {
        switch self {
        case .allCountry: "日本を含む世界中の株式"
        case .sp500: "米国の代表的な大企業 約500社"
        case .topix: "日本の株式市場全体"
        case .nasdaq100: "ナスダック上場の大企業 約100社（ハイテク中心）"
        case .nikkei225: "日本を代表する225社"
        case .gold: "金（ゴールド）"
        case .emerging: "中国・インド・台湾などの新興国の株式"
        case .nanotech: "国内外のナノテクノロジー関連企業"
        case .genomics: "国内外の遺伝子工学関連企業"
        case .developedBond: "日本を除く先進国の国債"
        }
    }

    func dataID(isSample: Bool) -> String {
        isSample ? "demo-\(rawValue)" : rawValue
    }
}

extension FundDescriptor {
    private var knownFund: InvestmentFund? {
        InvestmentFund.allCases.first { id == $0.dataID(isSample: false) || id == $0.dataID(isSample: true) }
    }

    // Known funds get a short label; anything delivered later falls back to its name.
    var shortName: String {
        guard let fund = knownFund else { return displayName }
        return fund.displayName + (id.hasPrefix("demo-") ? "（サンプル）" : "")
    }

    // A fund delivered later has no plain summary yet, so its full name says what it is.
    var summary: String { knownFund?.summary ?? displayName }
}
