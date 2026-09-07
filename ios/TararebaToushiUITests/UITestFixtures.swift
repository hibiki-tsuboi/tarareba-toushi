import Foundation
import XCTest

// Only the UI test runner owns these fictional responses; it supplies them at launch.
enum UITestFixtures {
    // One catalog request plus one history per fund in the fixture below.
    static let requestsPerUpdate = 11

    @MainActor static func app(mode: String = "sample", session: UUID = UUID()) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["TARAREBA_TEST_MODE"] = mode
        app.launchEnvironment["TARAREBA_TEST_SESSION"] = session.uuidString
        app.launchEnvironment["TARAREBA_TEST_RESPONSES"] = responses(mode: mode)
        return app
    }

    private static func responses(mode: String) -> String {
        let sample = mode == "sample"
        let ids = sample
            ? ["demo-all-country", "demo-sp500", "demo-topix", "demo-nasdaq100", "demo-nikkei225", "demo-gold", "demo-emerging", "demo-nanotech", "demo-genomics", "demo-developed-bond"]
            : ["all-country", "sp500", "topix", "nasdaq100", "nikkei225", "gold", "emerging", "nanotech", "genomics", "developed-bond"]
        let names = sample
            ? ["オルカン（サンプル）", "S&P500（サンプル）", "TOPIX（サンプル）", "NASDAQ100（サンプル）",
                "日経平均（サンプル）", "純金（サンプル）", "新興国株（サンプル）",
                "ナノテク（サンプル）", "遺伝子工学（サンプル）",
                "先進国債券（サンプル）"] : [
                "eMAXIS Slim 全世界株式（オール・カントリー）", "eMAXIS Slim 米国株式（S&P500）",
                "ｅＭＡＸＩＳ Ｓｌｉｍ 国内株式（ＴＯＰＩＸ）", "ｅＭＡＸＩＳ ＮＡＳＤＡＱ１００インデックス",
                "ｅＭＡＸＩＳ Ｓｌｉｍ 国内株式（日経平均）", "三菱ＵＦＪ 純金ファンド",
                "ｅＭＡＸＩＳ Ｓｌｉｍ 新興国株式インデックス", "ｅＭＡＸＩＳ Ｎｅｏ ナノテクノロジー",
                "ｅＭＡＸＩＳ Ｎｅｏ 遺伝子工学",
                "ｅＭＡＸＩＳ Ｓｌｉｍ 先進国債券インデックス（除く日本）",
            ]
        let dates = ["2020-01-06", "2021-09-06", "2023-09-04", "2025-01-06", "2025-08-13", "2026-09-03", "2026-09-04"]
        let values = [["7000", "8000", "9000", "10000", "15000", "11900", "12000"],
            ["6000", "7000", "8000", "10000", "16000", "13900", "14000"],
            ["8000", "9000", "9500", "10000", "12000", "10900", "11000"],
            ["5000", "6000", "7000", "10000", "18000", "15900", "16000"],
            ["9000", "9500", "9800", "10000", "13000", "12900", "13000"],
            ["4000", "5000", "6000", "10000", "20000", "16900", "17000"],
            ["7500", "8500", "9200", "10000", "19000", "17900", "18000"],
            ["3000", "4500", "6500", "10000", "22000", "18900", "19000"],
            ["6500", "7500", "8800", "10000", "21000", "19900", "20000"],
            ["9500", "9700", "9900", "10000", "10500", "10400", "21000"]]
        let version = "ui-fixture-v1"
        // Hexadecimal only: a contentVersion must match ^fund-[a-f0-9]{64}$.
        let contentVersions = ["a", "b", "c", "d", "e", "f", "0", "1", "2", "3"].map { "fund-" + String(repeating: $0, count: 64) }
        let descriptors: [[String: Any]] = ids.enumerated().map { index, id in
            var descriptor: [String: Any] = ["id": id, "displayName": names[index], "currency": "JPY",
                "path": sample ? "funds/\(id).\(version).json" : "funds/\(id).json",
                "firstDate": dates[0], "lastDate": dates[dates.count - 1]]
            if !sample { descriptor["contentVersion"] = contentVersions[index] }
            return descriptor
        }
        let manifest: [String: Any] = ["schemaVersion": sample ? 1 : 2, "datasetVersion": version, "isSample": sample,
            "publishedAt": "2026-09-06T00:00:00Z", "funds": descriptors]
        var result = ["/\(mode)/manifest.json": json(manifest)]
        for (index, id) in ids.enumerated() {
            let source: [String: Any] = ["kind": sample ? "synthetic" : "official", "name": "自動テスト用の架空値",
                "url": "https://example.com/fund", "note": "UIテスト用の固定値です。実際の運用実績ではありません。"]
            let series: [String: Any] = ["schemaVersion": sample ? 1 : 2, "datasetVersion": sample ? version : contentVersions[index], "isSample": sample,
                "fundId": id, "currency": "JPY", "valueBasis": sample ? "reinvestedIndex" : "nav", "source": source,
                "observations": zip(dates, values[index]).map { ["date": $0.0, "value": $0.1] }]
            let path = sample ? "funds/\(id).\(version).json" : "funds/\(id).json"
            result["/\(mode)/\(path)"] = json(series)
        }
        return json(result)
    }

    private static func json(_ value: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
}
