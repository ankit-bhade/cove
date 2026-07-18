import SwiftUI
import XCTest
@testable import Cove

final class AppearanceSettingTests: XCTestCase {
    func testSystemFollowsThePlatformAppearance() {
        XCTAssertNil(AppearanceSetting.system.colorScheme)
    }

    func testLightAndDarkForceTheirScheme() {
        XCTAssertEqual(AppearanceSetting.light.colorScheme, .light)
        XCTAssertEqual(AppearanceSetting.dark.colorScheme, .dark)
    }

    func testRawValuesRoundTripForStorage() {
        // The raw value is what @AppStorage persists; a rename would
        // silently reset every user's saved preference.
        XCTAssertEqual(AppearanceSetting(rawValue: "system"), .system)
        XCTAssertEqual(AppearanceSetting(rawValue: "light"), .light)
        XCTAssertEqual(AppearanceSetting(rawValue: "dark"), .dark)
        XCTAssertNil(AppearanceSetting(rawValue: "sepia"))
    }
}
