import Foundation
import XCTest

// Only the UI test runner owns these fictional responses; it supplies them at launch.
enum UITestFixtures {
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
        let ids = sample ? ["demo-all-country", "demo-sp500"] : ["all-country", "sp500"]
        let names = sample ? ["オルカン（サンプル）", "S&P500（サンプル）"] : [
            "eMAXIS Slim 全世界株式（オール・カントリー）", "eMAXIS Slim 米国株式（S&P500）",
        ]
        let dates = ["2020-01-06", "2021-09-06", "2023-09-04", "2025-01-06", "2025-08-13", "2026-09-03", "2026-09-04"]
        let values = [["7000", "8000", "9000", "10000", "15000", "11900", "12000"],
            ["6000", "7000", "8000", "10000", "16000", "13900", "14000"]]
        let version = "ui-fixture-v1"
        let descriptors: [[String: Any]] = ids.enumerated().map { index, id in
            ["id": id, "displayName": names[index], "currency": "JPY", "path": "funds/\(id).\(version).json",
                "firstDate": dates[0], "lastDate": dates[dates.count - 1]]
        }
        let manifest: [String: Any] = ["schemaVersion": 1, "datasetVersion": version, "isSample": sample,
            "publishedAt": "2026-09-06T00:00:00Z", "funds": descriptors]
        var result = ["/\(mode)/manifest.json": json(manifest)]
        for (index, id) in ids.enumerated() {
            let source: [String: Any] = ["kind": sample ? "synthetic" : "official", "name": "自動テスト用の架空値",
                "url": "https://example.com/fund", "note": "UIテスト用の固定値です。実際の運用実績ではありません。"]
            let series: [String: Any] = ["schemaVersion": 1, "datasetVersion": version, "isSample": sample,
                "fundId": id, "currency": "JPY", "valueBasis": sample ? "reinvestedIndex" : "nav", "source": source,
                "observations": zip(dates, values[index]).map { ["date": $0.0, "value": $0.1] }]
            result["/\(mode)/funds/\(id).\(version).json"] = json(series)
        }
        return json(result)
    }

    private static func json(_ value: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
}
