import Foundation
import XCTest

// Only the UI test runner owns these fictional responses; it supplies them at launch.
enum UITestFixtures {
    // One catalog request plus one history per fund in the fixture below.
    static let requestsPerUpdate = 4

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
            ? ["demo-all-country", "demo-sp500", "demo-topix"] : ["all-country", "sp500", "topix"]
        let names = sample ? ["オルカン（サンプル）", "S&P500（サンプル）", "TOPIX（サンプル）"] : [
            "eMAXIS Slim 全世界株式（オール・カントリー）", "eMAXIS Slim 米国株式（S&P500）",
            "ｅＭＡＸＩＳ Ｓｌｉｍ 国内株式（ＴＯＰＩＸ）",
        ]
        let dates = ["2020-01-06", "2021-09-06", "2023-09-04", "2025-01-06", "2025-08-13", "2026-09-03", "2026-09-04"]
        let values = [["7000", "8000", "9000", "10000", "15000", "11900", "12000"],
            ["6000", "7000", "8000", "10000", "16000", "13900", "14000"],
            ["8000", "9000", "9500", "10000", "12000", "10900", "11000"]]
        let version = "ui-fixture-v1"
        let contentVersions = ["a", "b", "c"].map { "fund-" + String(repeating: $0, count: 64) }
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
