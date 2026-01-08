import XCTest

final class MobileOdooUITests: XCTestCase {
    func testLaunchShowsLogin() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Odoo Mobile"].waitForExistence(timeout: 2))
    }
}
