// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class PickerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    func testCancelReopenAndConfirmSelection() {
        exercise(XCUIApplication())
    }
    func testQtWindowCancelReopenAndConfirmSelection() {
        exercise(XCUIApplication(bundleIdentifier: "com.cui.freekill.tests.qtpicker"))
    }
    private func exercise(_ app: XCUIApplication) {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        for attempt in 1...3 {
            let open = app.buttons["Choose background"]
            XCTAssertTrue(open.waitForExistence(timeout: 15), app.debugDescription)
            if attempt == 3 && app.textFields["Game chat"].exists {
                app.textFields["Game chat"].tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            }
            open.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 15), app.debugDescription)
            // A startup regression must fail before we click Cancel ourselves.
            if attempt == 1 {
                let unexpectedlyGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
                XCTAssertEqual(XCTWaiter.wait(for: [unexpectedlyGone], timeout: 8), .timedOut, app.debugDescription)
            }
            if attempt == 2 {
                let search = app.searchFields.firstMatch
                if search.exists {
                    search.tap()
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
                }
            }
            cancel.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Cancelled \(attempt)")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
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
            let expected = "\(attempt == 4 ? "Cancelled" : "Selected") \(attempt)"
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", expected)).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        }
        // Only the Qt host has the actual BGSetting page's other image routes.
        if app.buttons["Choose room background"].exists {
            for (index, name) in ["Choose room background", "Choose portrait"].enumerated() {
                app.buttons[name].tap()
                let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
                XCTAssertTrue(photo.waitForExistence(timeout: 15), app.debugDescription)
                photo.tap()
                let confirm = app.alerts["使用所选背景？"]
                XCTAssertTrue(confirm.waitForExistence(timeout: 15), app.debugDescription)
                confirm.buttons["确认"].tap()
                XCTAssertTrue(app.staticTexts["Selected \(index + 6)"].waitForExistence(timeout: 15), app.debugDescription)
            }
        }
    }
}
