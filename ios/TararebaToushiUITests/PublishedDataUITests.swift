import XCTest

// Opt-in deployment verification. Ordinary test runs remain independent of the network.
final class PublishedDataUITests: XCTestCase {
    private struct Expectation: Decodable {
        let version: String
        let date: String
        let amount: String
        let allCountryValuation: String
        let sp500Valuation: String
    }

    @MainActor func testPublishedNAVAndOfflineRelaunch() throws {
        guard let text = ProcessInfo.processInfo.environment["TARAREBA_PUBLISHED_EXPECTATION"] else {
            throw XCTSkip("公開版の検証時だけTARAREBA_PUBLISHED_EXPECTATIONを指定してください。")
        }
        let expected = try JSONDecoder().decode(Expectation.self, from: Data(text.utf8))
        let app = UITestFixtures.app(mode: "live")
        app.launchEnvironment.removeValue(forKey: "TARAREBA_TEST_RESPONSES")
        app.launchEnvironment["TARAREBA_TEST_DATE"] = expected.date
        app.launchEnvironment["TARAREBA_TEST_AMOUNT"] = expected.amount
        app.launch()
        waitForSimulation(app)
        verifyVersion(expected.version, in: app)

        app.buttons["simulate"].tap()
        let allCountry = app.staticTexts["valuation-all-country"]
        XCTAssertTrue(allCountry.waitForExistence(timeout: 5))
        XCTAssertEqual(allCountry.label, expected.allCountryValuation)
        let sp500 = app.staticTexts["valuation-sp500"]
        XCTAssertTrue(sp500.waitForExistence(timeout: 5))
        XCTAssertEqual(sp500.label, expected.sp500Valuation)
        capture(app, name: "published-nav-comparison")

        app.terminate()
        app.launchEnvironment["TARAREBA_TEST_OFFLINE"] = "1"
        app.launch()
        waitForSimulation(app)
        verifyVersion(expected.version, in: app)
        app.buttons["simulate"].tap()
        XCTAssertTrue(allCountry.waitForExistence(timeout: 5))
        XCTAssertEqual(allCountry.label, expected.allCountryValuation)
        XCTAssertTrue(sp500.waitForExistence(timeout: 5))
        XCTAssertEqual(sp500.label, expected.sp500Valuation)
        capture(app, name: "published-nav-offline")
    }

    @MainActor private func waitForSimulation(_ app: XCUIApplication) {
        let button = app.buttons["simulate"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 60), .completed)
    }

    @MainActor private func verifyVersion(_ version: String, in app: XCUIApplication) {
        app.buttons["data-info"].tap()
        XCTAssertTrue(app.navigationBars["データと計算について"].waitForExistence(timeout: 5))
        let value = app.staticTexts[version]
        for _ in 0..<12 {
            if value.exists && value.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(value.exists)
        XCTAssertTrue(value.isHittable)
        capture(app, name: "published-nav-version")
        app.buttons["閉じる"].tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
