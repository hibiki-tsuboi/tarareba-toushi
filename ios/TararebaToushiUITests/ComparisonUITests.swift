import XCTest

final class ComparisonUITests: XCTestCase {
    @MainActor func testInputThenMinimalResultsAndAttribution() {
        let app = UITestFixtures.app(mode: "live")
        app.launch()
        waitForSimulation(app)
        XCTAssertTrue(app.textFields["investment-amount"].exists)
        XCTAssertTrue(app.datePickers["investment-date"].exists)
        XCTAssertFalse(app.staticTexts["valuation-all-country"].exists)
        XCTAssertFalse(app.buttons["preset-5"].exists)
        capture(app, name: "simple-input")

        simulate(app)
        XCTAssertTrue(app.staticTexts["profit-all-country"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profit-all-country"].label, "＋200,000円")
        XCTAssertEqual(app.staticTexts["valuation-all-country"].label, "1,200,000円")
        XCTAssertEqual(app.staticTexts["profit-sp500"].label, "＋400,000円")
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "1,400,000円")
        XCTAssertFalse(app.textFields["investment-amount"].exists)
        XCTAssertFalse(app.datePickers["investment-date"].exists)
        XCTAssertFalse(app.buttons["simulate"].exists)
        XCTAssertFalse(app.staticTexts["comparison-difference"].exists)
        XCTAssertFalse(app.buttons["前の観測日"].exists)
        capture(app, name: "simple-results")

        app.buttons["data-info"].tap()
        XCTAssertTrue(app.navigationBars["データと計算について"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["refresh-data"].exists)
        capture(app, name: "simple-data-information")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.staticTexts["valuation-all-country"].waitForExistence(timeout: 5))
    }

    @MainActor func testInvalidAmountAndResimulation() {
        let app = UITestFixtures.app()
        app.launch()
        simulate(app)
        let valuation = app.staticTexts["valuation-demo-all-country"]
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        tapVisible(app.buttons["edit-input"], in: app)

        let amount = app.textFields["investment-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "1,000,000")
        XCTAssertFalse(valuation.exists)
        replaceAmount(in: app, with: "0")
        XCTAssertFalse(app.staticTexts["input-error"].exists)
        simulate(app)
        XCTAssertTrue(app.staticTexts["input-error"].waitForExistence(timeout: 3))
        XCTAssertTrue(amount.exists)
        XCTAssertFalse(valuation.exists)

        replaceAmount(in: app, with: "2000000")
        XCTAssertFalse(valuation.exists)
        simulate(app)
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        XCTAssertEqual(valuation.label, "2,400,000円")
        XCTAssertEqual(app.staticTexts["profit-demo-all-country"].label, "＋400,000円")
        tapVisible(app.buttons["edit-input"], in: app)
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "2,000,000")
        XCTAssertFalse(app.staticTexts["input-error"].exists)
    }

    @MainActor func testZeroGainAndUpdateFailurePreservesResults() {
        let app = UITestFixtures.app()
        app.launchEnvironment["TARAREBA_TEST_FAIL_AFTER"] = "3"
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2026-09-04"
        app.launch()
        simulate(app)
        let profit = app.staticTexts["profit-demo-all-country"]
        XCTAssertTrue(profit.waitForExistence(timeout: 5))
        XCTAssertEqual(profit.label, "0円")
        XCTAssertEqual(app.staticTexts["profit-demo-sp500"].label, "0円")
        XCTAssertEqual(app.staticTexts["valuation-demo-all-country"].label, "1,000,000円")
        app.buttons["data-info"].tap()
        let refresh = app.buttons["refresh-data"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        XCTAssertTrue(app.staticTexts["update-message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["update-message"].label.contains("404"))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(profit.waitForExistence(timeout: 5))
        XCTAssertEqual(profit.label, "0円")
    }

    @MainActor func testLargeTextLayout() {
        let app = UITestFixtures.app()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 10))
        capture(app, name: "simple-accessibility-input")
        simulate(app)
        XCTAssertTrue(app.staticTexts["profit-demo-all-country"].waitForExistence(timeout: 5))
        capture(app, name: "simple-accessibility-results")
        let secondValuation = app.staticTexts["valuation-demo-sp500"]
        reveal(secondValuation, in: app)
        XCTAssertEqual(secondValuation.label, "1,400,000円")
        capture(app, name: "simple-accessibility-results-scrolled")
        tapVisible(app.buttons["edit-input"], in: app)
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 5))
    }

    @MainActor func testLossScenario() {
        let app = UITestFixtures.app()
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2025-08-13"
        app.launch()
        simulate(app)
        XCTAssertTrue(app.staticTexts["profit-demo-all-country"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profit-demo-all-country"].label, "−200,000円")
        XCTAssertEqual(app.staticTexts["valuation-demo-all-country"].label, "800,000円")
        XCTAssertEqual(app.staticTexts["profit-demo-sp500"].label, "−125,000円")
        capture(app, name: "simple-loss-results")
    }

    @MainActor func testFirstLaunchOfflineHasNoResultsAndRetryRequiresSimulation() {
        let app = UITestFixtures.app(mode: "live")
        app.launchEnvironment["TARAREBA_TEST_FAIL_FIRST"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["initial-data-unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["simulate"].isEnabled)
        XCTAssertFalse(app.staticTexts["valuation-all-country"].exists)
        XCTAssertEqual(app.staticTexts["update-message"].label,
            "インターネットに接続できません。接続を確認して再試行してください。")
        capture(app, name: "simple-first-launch-offline")
        tapVisible(app.buttons["refresh-data"], in: app)
        waitForSimulation(app)
        XCTAssertFalse(app.staticTexts["valuation-all-country"].exists)
        XCTAssertFalse(app.staticTexts["initial-data-unavailable"].exists)
        simulate(app)
        XCTAssertTrue(app.staticTexts["valuation-all-country"].waitForExistence(timeout: 5))
    }

    @MainActor func testDownloadedCacheWorksAfterOfflineRelaunch() {
        let app = UITestFixtures.app(mode: "live")
        app.launch()
        simulate(app)
        let valuation = app.staticTexts["valuation-all-country"]
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        let value = valuation.label
        app.terminate()
        app.launchEnvironment["TARAREBA_TEST_OFFLINE"] = "1"
        app.launch()
        waitForSimulation(app)
        XCTAssertFalse(valuation.exists)
        XCTAssertTrue(app.textFields["investment-amount"].exists)
        simulate(app)
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        XCTAssertEqual(valuation.label, value)
    }

    @MainActor func testUnavailableDateStaysOnInput() {
        let app = UITestFixtures.app()
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2026-09-05"
        app.launch()
        waitForSimulation(app)
        XCTAssertFalse(app.staticTexts["input-error"].exists)
        simulate(app)
        XCTAssertTrue(app.staticTexts["input-error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["input-error"].label.contains("この期間のデータがありません"))
        XCTAssertTrue(app.datePickers["investment-date"].exists)
        XCTAssertFalse(app.staticTexts["valuation-demo-all-country"].exists)
    }

    @MainActor private func waitForSimulation(_ app: XCUIApplication) {
        let button = app.buttons["simulate"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
    }

    @MainActor private func simulate(_ app: XCUIApplication) {
        waitForSimulation(app)
        tapVisible(app.buttons["simulate"], in: app)
    }

    @MainActor private func replaceAmount(in app: XCUIApplication, with text: String) {
        let amount = app.textFields["investment-amount"]
        amount.tap()
        if let value = amount.value as? String {
            amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        amount.typeText(text)
        app.buttons["完了"].tap()
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
