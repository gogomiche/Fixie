import XCTest
@testable import Fixie

final class DiffCalculatorTests: XCTestCase {

    // MARK: - Basic Diff Tests

    func testDiff_identicalStrings() {
        let diff = DiffCalculator.calculateDiff(original: "Hello World", corrected: "Hello World")

        XCTAssertEqual(diff.count, 1)
        XCTAssertEqual(diff[0].type, .unchanged)
        XCTAssertEqual(diff[0].text, "Hello World")
    }

    func testDiff_addedWord() {
        let diff = DiffCalculator.calculateDiff(original: "Hello", corrected: "Hello World")

        // Should have: "Hello" (unchanged) + " World" (added)
        let hasUnchanged = diff.contains { $0.type == .unchanged && $0.text.contains("Hello") }
        let hasAdded = diff.contains { $0.type == .added && $0.text.contains("World") }

        XCTAssertTrue(hasUnchanged)
        XCTAssertTrue(hasAdded)
    }

    func testDiff_removedWord() {
        let diff = DiffCalculator.calculateDiff(original: "Hello World", corrected: "Hello")

        // Should have: "Hello" (unchanged) + " World" (removed)
        let hasUnchanged = diff.contains { $0.type == .unchanged && $0.text.contains("Hello") }
        let hasRemoved = diff.contains { $0.type == .removed && $0.text.contains("World") }

        XCTAssertTrue(hasUnchanged)
        XCTAssertTrue(hasRemoved)
    }

    func testDiff_changedWord() {
        let diff = DiffCalculator.calculateDiff(original: "Helo World", corrected: "Hello World")

        // Should have: "Helo" (removed) + "Hello" (added) + " World" (unchanged)
        let hasRemoved = diff.contains { $0.type == .removed && $0.text.contains("Helo") }
        let hasAdded = diff.contains { $0.type == .added && $0.text.contains("Hello") }
        let hasUnchanged = diff.contains { $0.type == .unchanged && $0.text.contains("World") }

        XCTAssertTrue(hasRemoved)
        XCTAssertTrue(hasAdded)
        XCTAssertTrue(hasUnchanged)
    }

    func testDiff_emptyOriginal() {
        let diff = DiffCalculator.calculateDiff(original: "", corrected: "Hello")

        XCTAssertTrue(diff.contains { $0.type == .added })
    }

    func testDiff_emptyCorrected() {
        let diff = DiffCalculator.calculateDiff(original: "Hello", corrected: "")

        XCTAssertTrue(diff.contains { $0.type == .removed })
    }

    func testDiff_preservesWhitespace() {
        let diff = DiffCalculator.calculateDiff(
            original: "Hello   World",
            corrected: "Hello World"
        )

        // Should detect the whitespace change
        XCTAssertFalse(diff.isEmpty)
    }

    func testDiff_multilineText() {
        let original = """
        Line one
        Line two
        """
        let corrected = """
        Line one
        Line three
        """

        let diff = DiffCalculator.calculateDiff(original: original, corrected: corrected)

        // Should detect changes in line two -> three
        XCTAssertTrue(diff.contains { $0.type == .removed && $0.text.contains("two") })
        XCTAssertTrue(diff.contains { $0.type == .added && $0.text.contains("three") })
    }
}
