// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class PickerTests: XCTestCase {
    func testCancelReopenAndConfirmSelection() {
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
            if attempt == 2 {
                let search = app.searchFields.firstMatch
                if search.exists {
                    search.tap()
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
                }
            }
            cancel.tap()
            let result = app.staticTexts["result"]
            let expected = NSPredicate(format: "label == %@", "Cancelled \(attempt)")
            expectation(for: expected, evaluatedWith: result)
            waitForExpectations(timeout: 15)
        }
        for attempt in 4...5 {
            app.buttons["Choose background"].tap()
            let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 15), app.debugDescription)
            photo.tap()
            let confirm = app.alerts["使用所选背景？"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 15), app.debugDescription)
            let action = attempt == 4 ? "取消" : "确认"
            confirm.buttons[action].tap()
            let expected = NSPredicate(format: "label == %@", "\(attempt == 4 ? "Cancelled" : "Selected") \(attempt)")
            expectation(for: expected, evaluatedWith: app.staticTexts["result"])
            waitForExpectations(timeout: 15)
        }
    }
}
