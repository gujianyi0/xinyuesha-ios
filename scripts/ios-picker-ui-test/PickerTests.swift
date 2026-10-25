// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class PickerTests: XCTestCase {
    func testSearchCancelAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        for attempt in 1...3 {
            let open = app.buttons["Choose background"]
            XCTAssertTrue(open.waitForExistence(timeout: 15))
            open.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(app.buttons["Add"].exists, "Explicit selection confirmation missing: \(app.debugDescription)")
            if attempt == 2 {
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
                search.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            }
            cancel.tap()
            let result = app.staticTexts["result"]
            let expected = NSPredicate(format: "label == %@", "Cancelled \(attempt)")
            expectation(for: expected, evaluatedWith: result)
            waitForExpectations(timeout: 15)
        }
    }
}
