@testable import MaestroCore
import XCTest

final class LocalizationKeysTests: XCTestCase {
    func testAllKeysHaveBothLanguagesNonEmpty() {
        for entry in LocalizationKeys.allKeys {
            XCTAssertFalse(entry.ko.isEmpty, "ko empty for key=\(entry.key)")
            XCTAssertFalse(entry.en.isEmpty, "en empty for key=\(entry.key)")
        }
    }

    func testNoDuplicateKeys() {
        let keys = LocalizationKeys.allKeys.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count,
                       "duplicate keys present: \(keys.sorted())")
    }

    func testKeysFollowDotNamespace() {
        for entry in LocalizationKeys.allKeys where entry.key != "app.title" {
            XCTAssertTrue(entry.key.contains("."),
                          "key '\(entry.key)' should be namespaced (contain '.')")
        }
    }

    func testLocalizedReturnsKoForKoreanLocale() {
        let entry = LocalizationKeys.Onboarding.welcomeTitle
        XCTAssertEqual(entry.localized(localeIdentifier: "ko_KR"), entry.ko)
    }

    func testLocalizedReturnsEnForEnglishLocale() {
        let entry = LocalizationKeys.Onboarding.welcomeTitle
        XCTAssertEqual(entry.localized(localeIdentifier: "en_US"), entry.en)
    }

    func testLocalizedDefaultsToEnForUnknownLocale() {
        let entry = LocalizationKeys.Common.cancel
        XCTAssertEqual(entry.localized(localeIdentifier: "fr_FR"), entry.en)
    }
}

final class A11yLabelsTests: XCTestCase {
    func testAllA11yLabelsHaveBothLanguagesNonEmpty() {
        for entry in A11yLabels.allLabels {
            XCTAssertFalse(entry.ko.isEmpty, "ko empty for a11y key=\(entry.key)")
            XCTAssertFalse(entry.en.isEmpty, "en empty for a11y key=\(entry.key)")
        }
    }

    func testA11yKeysAreNamespacedAsA11y() {
        for entry in A11yLabels.allLabels {
            XCTAssertTrue(entry.key.hasPrefix("a11y."),
                          "a11y key '\(entry.key)' should start with 'a11y.'")
        }
    }

    func testA11yKeysDoNotCollideWithUIKeys() {
        let uiKeys = Set(LocalizationKeys.allKeys.map(\.key))
        let a11yKeys = Set(A11yLabels.allLabels.map(\.key))
        XCTAssertTrue(uiKeys.isDisjoint(with: a11yKeys),
                      "a11y keys collide with UI keys: \(uiKeys.intersection(a11yKeys))")
    }
}
