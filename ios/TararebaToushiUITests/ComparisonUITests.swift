import XCTest

final class ComparisonUITests: XCTestCase {
    @MainActor func testInputThenBothResultsDifferenceAndAttribution() {
        let app = UITestFixtures.app(mode: "live")
        app.launch()
        waitForSimulation(app)
        XCTAssertTrue(app.textFields["investment-amount"].exists)
        XCTAssertTrue(app.datePickers["investment-date"].exists)
        XCTAssertEqual(app.buttons["simulate"].label, "2つを比較する")
        XCTAssertTrue(app.buttons["fund-all-country"].isSelected)
        XCTAssertTrue(app.buttons["fund-sp500"].isSelected)
        XCTAssertEqual(app.staticTexts["fund-selection-count"].label, "8商品中2商品を選択中")
        XCTAssertFalse(app.staticTexts["valuation-all-country"].exists)
        XCTAssertFalse(app.buttons["preset-5"].exists)
        capture(app, name: "comparison-input")

        simulate(app)
        XCTAssertTrue(app.staticTexts["profit-all-country"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profit-all-country"].label, "＋200,000円")
        XCTAssertEqual(app.staticTexts["valuation-all-country"].label, "1,200,000円")
        XCTAssertEqual(app.staticTexts["profit-sp500"].label, "＋400,000円")
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "1,400,000円")
        XCTAssertFalse(app.textFields["investment-amount"].exists)
        XCTAssertFalse(app.datePickers["investment-date"].exists)
        XCTAssertFalse(app.buttons["simulate"].exists)
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "200,000円")
        XCTAssertEqual(app.staticTexts["comparison-summary"].label, "この期間では、S&P500のほうが多い結果でした。")
        let allCountryFrame = app.staticTexts["profit-all-country"].frame
        let sp500Frame = app.staticTexts["profit-sp500"].frame
        if app.frame.width > 600 {
            XCTAssertEqual(allCountryFrame.minY, sp500Frame.minY, accuracy: 2)
            XCTAssertLessThan(allCountryFrame.maxX, sp500Frame.minX)
        } else {
            XCTAssertLessThan(allCountryFrame.maxY, sp500Frame.minY)
            XCTAssertEqual(allCountryFrame.minX, sp500Frame.minX, accuracy: 2)
        }
        XCTAssertFalse(app.buttons["前の観測日"].exists)
        capture(app, name: "comparison-results")

        app.buttons["data-info"].tap()
        XCTAssertTrue(app.navigationBars["データと計算について"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["refresh-data"].exists)
        capture(app, name: "comparison-data-information")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.staticTexts["valuation-all-country"].waitForExistence(timeout: 5))
    }

    @MainActor func testCheckingOneFundShowsOnlyThatResultAndNoDifference() {
        let app = UITestFixtures.app(mode: "live")
        app.launch()
        waitForSimulation(app)
        tapVisible(app.buttons["fund-all-country"], in: app)
        XCTAssertFalse(app.buttons["fund-all-country"].isSelected)
        XCTAssertEqual(app.buttons["simulate"].label, "結果を見る")
        capture(app, name: "single-fund-input")

        simulate(app)
        XCTAssertTrue(app.staticTexts["valuation-sp500"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "1,400,000円")
        XCTAssertFalse(app.staticTexts["valuation-all-country"].exists)
        XCTAssertFalse(app.staticTexts["comparison-difference"].exists)
        XCTAssertFalse(app.staticTexts["comparison-summary"].exists)
        capture(app, name: "single-fund-results")

        // The last remaining fund cannot be cleared.
        tapVisible(app.buttons["edit-input"], in: app)
        // The pop back to the input screen swallows a tap while it is still animating.
        waitForSimulation(app)
        XCTAssertTrue(app.buttons["fund-sp500"].waitForExistence(timeout: 5))
        tapVisible(app.buttons["fund-sp500"], in: app)
        XCTAssertTrue(app.buttons["fund-sp500"].isSelected)
        XCTAssertTrue(app.staticTexts["input-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["input-error"].label, "商品を1つ以上選んでください。")

        // The selection survives a relaunch.
        app.terminate()
        app.launch()
        waitForSimulation(app)
        XCTAssertFalse(app.buttons["fund-all-country"].isSelected)
        XCTAssertTrue(app.buttons["fund-sp500"].isSelected)
    }

    @MainActor func testCheckingAThirdFundRanksResultsAndShowsTheWidestGap() {
        let app = UITestFixtures.app(mode: "live")
        app.launch()
        waitForSimulation(app)
        tapVisible(app.buttons["fund-topix"], in: app)
        XCTAssertTrue(app.buttons["fund-topix"].isSelected)
        XCTAssertEqual(app.staticTexts["fund-selection-count"].label, "8商品中3商品を選択中")
        XCTAssertEqual(app.buttons["simulate"].label, "3つを比較する")

        simulate(app)
        XCTAssertTrue(app.staticTexts["valuation-topix"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["valuation-all-country"].label, "1,200,000円")
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "1,400,000円")
        XCTAssertEqual(app.staticTexts["valuation-topix"].label, "1,100,000円")
        // Three funds report the widest gap and a ranking instead of a difference.
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "300,000円")
        XCTAssertEqual(app.staticTexts["comparison-summary"].label, "この期間で最も多かったのはS&P500でした。")
        let ranks = ["rank-sp500", "rank-all-country", "rank-topix"].map {
            app.descendants(matching: .any).matching(identifier: $0).firstMatch.frame.minY
        }
        XCTAssertEqual(ranks, ranks.sorted(), "the ranking is ordered by valuation")
        capture(app, name: "three-fund-results")
    }

    @MainActor func testBothFundsUseChangedAmountAndPreserveInput() {
        let app = UITestFixtures.app(mode: "live")
        app.launch()
        waitForSimulation(app)
        let date = app.datePickers["investment-date"].value as? String
        XCTAssertFalse(app.staticTexts["valuation-sp500"].exists)

        simulate(app)
        XCTAssertTrue(app.staticTexts["profit-sp500"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profit-sp500"].label, "＋400,000円")
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "1,400,000円")
        XCTAssertEqual(app.staticTexts["valuation-all-country"].label, "1,200,000円")

        tapVisible(app.buttons["edit-input"], in: app)
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["investment-amount"].value as? String, "1,000,000")
        XCTAssertEqual(app.datePickers["investment-date"].value as? String, date)
        replaceAmount(in: app, with: "2000000")
        XCTAssertFalse(app.staticTexts["valuation-all-country"].exists)
        simulate(app)
        XCTAssertTrue(app.staticTexts["valuation-all-country"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["valuation-all-country"].label, "2,400,000円")
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "2,800,000円")
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "400,000円")
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
        let sp500Valuation = app.staticTexts["valuation-demo-sp500"]
        XCTAssertTrue(sp500Valuation.waitForExistence(timeout: 5))
        XCTAssertEqual(sp500Valuation.label, "2,800,000円")
        XCTAssertEqual(app.staticTexts["profit-demo-sp500"].label, "＋800,000円")
        XCTAssertEqual(valuation.label, "2,400,000円")
        tapVisible(app.buttons["edit-input"], in: app)
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "2,000,000")
        XCTAssertFalse(app.staticTexts["input-error"].exists)
    }

    @MainActor func testZeroGainAndUpdateFailurePreservesResults() {
        let app = UITestFixtures.app()
        // Let the first load finish, then fail the refresh that follows it.
        app.launchEnvironment["TARAREBA_TEST_FAIL_AFTER"] = String(UITestFixtures.requestsPerUpdate)
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2026-09-04"
        app.launch()
        simulate(app)
        let profit = app.staticTexts["profit-demo-all-country"]
        XCTAssertTrue(profit.waitForExistence(timeout: 5))
        XCTAssertEqual(profit.label, "0円")
        XCTAssertEqual(app.staticTexts["profit-demo-sp500"].label, "0円")
        XCTAssertEqual(app.staticTexts["valuation-demo-all-country"].label, "1,000,000円")
        XCTAssertEqual(app.staticTexts["valuation-demo-sp500"].label, "1,000,000円")
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "0円")
        XCTAssertEqual(app.staticTexts["comparison-summary"].label, "表示上の差額は0円。同じ結果でした。")
        app.buttons["data-info"].tap()
        let refresh = app.buttons["refresh-data"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        XCTAssertTrue(app.staticTexts["update-message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["update-message"].label.contains("404"))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(profit.waitForExistence(timeout: 5))
        XCTAssertEqual(profit.label, "0円")
        XCTAssertEqual(app.staticTexts["profit-demo-sp500"].label, "0円")
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "0円")
    }

    @MainActor func testLargeTextLayout() {
        let app = UITestFixtures.app()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["investment-amount"].waitForExistence(timeout: 10))
        waitForSimulation(app)
        capture(app, name: "comparison-accessibility-input")
        simulate(app)
        XCTAssertTrue(app.staticTexts["profit-demo-all-country"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profit-demo-all-country"].label, "＋200,000円")
        capture(app, name: "comparison-accessibility-results")
        let valuation = app.staticTexts["valuation-demo-sp500"]
        reveal(valuation, in: app)
        XCTAssertEqual(valuation.label, "1,400,000円")
        XCTAssertEqual(app.staticTexts["profit-demo-sp500"].label, "＋400,000円")
        capture(app, name: "comparison-accessibility-results-scrolled")
        reveal(app.staticTexts["comparison-difference"], in: app)
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "200,000円")
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
        XCTAssertEqual(app.staticTexts["valuation-demo-sp500"].label, "875,000円")
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "75,000円")
        capture(app, name: "comparison-loss-results")
    }

    @MainActor func testAllCountryHasHigherValuationWithoutChangingOrder() {
        let app = UITestFixtures.app(mode: "live")
        app.launchEnvironment["TARAREBA_TEST_DATE"] = "2026-09-03"
        app.launch()
        simulate(app)
        XCTAssertTrue(app.staticTexts["valuation-all-country"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["valuation-all-country"].label, "1,008,403円")
        XCTAssertEqual(app.staticTexts["valuation-sp500"].label, "1,007,194円")
        XCTAssertEqual(app.staticTexts["comparison-difference"].label, "1,209円")
        XCTAssertEqual(app.staticTexts["comparison-summary"].label, "この期間では、オルカンのほうが多い結果でした。")
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
        waitForSimulation(app)
        simulate(app)
        let valuation = app.staticTexts["valuation-sp500"]
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        let values = [app.staticTexts["valuation-all-country"].label, valuation.label,
            app.staticTexts["comparison-difference"].label]
        app.terminate()
        app.launchEnvironment["TARAREBA_TEST_OFFLINE"] = "1"
        app.launch()
        waitForSimulation(app)
        XCTAssertFalse(valuation.exists)
        XCTAssertTrue(app.textFields["investment-amount"].exists)
        simulate(app)
        XCTAssertTrue(valuation.waitForExistence(timeout: 5))
        XCTAssertEqual([app.staticTexts["valuation-all-country"].label, valuation.label,
            app.staticTexts["comparison-difference"].label], values)
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

    // A row scrolled under the status bar still reports itself hittable, but a tap on
    // its centre lands on the bar instead of the row. Keep the whole element below that.
    private static let tappableTop: CGFloat = 80

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let top = app.windows.firstMatch.frame.minY + Self.tappableTop
        for _ in 0..<8 {
            guard element.isHittable else { app.swipeUp(); continue }
            if element.frame.minY >= top { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable && element.frame.minY >= top)
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
