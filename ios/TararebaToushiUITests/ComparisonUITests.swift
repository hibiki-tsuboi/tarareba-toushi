import XCTest

final class ComparisonUITests: XCTestCase {
    @MainActor func testLiveComparisonAndAttributionOffline() {
        let app = XCUIApplication()
        app.launchArguments = ["--offline-live", "--ui-testing"]
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2025-01-01"
        app.launchEnvironment["TARAREBA_TEST_AMOUNT"] = "1,000,000"
        app.launch()
        XCTAssertTrue(app.staticTexts["valuation-all-country"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["valuation-sp500"].exists)
        XCTAssertFalse(app.staticTexts["valuation-demo-all-country"].exists)
        app.buttons["data-info"].tap()
        XCTAssertTrue(app.navigationBars["データと計算について"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["実データ"].exists)
        let information = XCTAttachment(screenshot: app.screenshot())
        information.name = "live-data-information"
        information.lifetime = .keepAlways
        add(information)
        app.buttons["閉じる"].tap()
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "live-comparison"
        top.lifetime = .keepAlways
        add(top)
        app.swipeUp()
        let comparison = XCTAttachment(screenshot: app.screenshot())
        comparison.name = "live-results"
        comparison.lifetime = .keepAlways
        add(comparison)
        app.swipeUp()
        let chart = XCTAttachment(screenshot: app.screenshot())
        chart.name = "live-chart"
        chart.lifetime = .keepAlways
        add(chart)
    }

    @MainActor func testOfflineComparisonAndInvalidAmount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--offline-sample", "--ui-testing"]
        app.launch()
        let amount = app.textFields["investment-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        let valuation = app.staticTexts["valuation-demo-all-country"]
        XCTAssertTrue(valuation.waitForExistence(timeout: 10))
        app.buttons["data-info"].tap()
        XCTAssertTrue(app.navigationBars["データと計算について"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        amount.tap()
        if let value = amount.value as? String {
            amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        amount.typeText("0")
        XCTAssertTrue(app.staticTexts["input-error"].waitForExistence(timeout: 3))
        XCTAssertFalse(valuation.exists)
        amount.typeText(XCUIKeyboardKey.delete.rawValue + "1000000")
        app.buttons["完了"].tap()
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        let before = valuation.label
        app.buttons["preset-5"].tap()
        XCTAssertNotEqual(valuation.label, before)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "comparison-iPhone"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.swipeUp()
        app.swipeUp()
        let chart = XCTAttachment(screenshot: app.screenshot())
        chart.name = "comparison-chart"
        chart.lifetime = .keepAlways
        add(chart)
    }

    @MainActor func testSinglePointChartAndUpdateFailure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--offline-sample", "--ui-testing"]
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2026-09-04"
        app.launch()
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 10))
        let difference = app.staticTexts["comparison-difference"]
        app.swipeUp()
        XCTAssertTrue(difference.waitForExistence(timeout: 10))
        XCTAssertEqual(difference.label, "0円")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "single-point-results"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.swipeUp()
        app.swipeUp()
        let refresh = app.buttons["refresh-data"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        XCTAssertTrue(app.staticTexts["update-message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["update-message"].label.contains("404"))
        let chart = XCTAttachment(screenshot: app.screenshot())
        chart.name = "single-point-chart-and-update-failure"
        chart.lifetime = .keepAlways
        add(chart)
    }

    @MainActor func testLargeTextLayout() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--offline-sample", "--ui-testing", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 10))
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "accessibility-text-input"
        top.lifetime = .keepAlways
        add(top)
        for _ in 0..<3 { app.swipeUp() }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "accessibility-text-results"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testLossScenarioAndChartSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--offline-sample", "--ui-testing"]
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2025-08-13"
        app.launch()
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "−")).firstMatch
                .waitForExistence(timeout: 5))
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "loss-comparison"
        result.lifetime = .keepAlways
        add(result)
        app.swipeUp()
        let previous = app.buttons["前の観測日"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        previous.tap()
        XCTAssertTrue(app.buttons["次の観測日"].isEnabled)
        let chart = XCTAttachment(screenshot: app.screenshot())
        chart.name = "selected-date-chart"
        chart.lifetime = .keepAlways
        add(chart)
    }
}
