import XCTest
@testable import Fixie

final class GrammarCheckStateTests: XCTestCase {

    // MARK: - GrammarCheckState Tests

    func testGrammarCheckState_isActive() {
        XCTAssertFalse(GrammarCheckState.idle.isActive)
        XCTAssertTrue(GrammarCheckState.capturing.isActive)
        XCTAssertTrue(GrammarCheckState.processing(progress: StreamProgress(originalText: "test")).isActive)
        XCTAssertFalse(GrammarCheckState.complete(result: GrammarResult(originalText: "test", correctedText: "test", provider: "Claude")).isActive)
        XCTAssertFalse(GrammarCheckState.error(.cancelled).isActive)
    }

    func testGrammarCheckState_canAccept() {
        XCTAssertFalse(GrammarCheckState.idle.canAccept)
        XCTAssertFalse(GrammarCheckState.capturing.canAccept)
        XCTAssertFalse(GrammarCheckState.processing(progress: StreamProgress(originalText: "test")).canAccept)
        XCTAssertTrue(GrammarCheckState.complete(result: GrammarResult(originalText: "test", correctedText: "test", provider: "Claude")).canAccept)
        XCTAssertFalse(GrammarCheckState.error(.cancelled).canAccept)
    }

    // MARK: - StreamProgress Tests

    func testStreamProgress_init() {
        let progress = StreamProgress(originalText: "Hello World")

        XCTAssertEqual(progress.originalText, "Hello World")
        XCTAssertEqual(progress.streamedText, "")
        XCTAssertEqual(progress.characterCount, 0)
        XCTAssertTrue(progress.isEmpty)
    }

    func testStreamProgress_append() {
        var progress = StreamProgress(originalText: "Original")

        progress.append("Hello")
        XCTAssertEqual(progress.streamedText, "Hello")
        XCTAssertEqual(progress.characterCount, 5)
        XCTAssertFalse(progress.isEmpty)

        progress.append(" World")
        XCTAssertEqual(progress.streamedText, "Hello World")
        XCTAssertEqual(progress.characterCount, 11)
    }

    // MARK: - GrammarResult Tests

    func testGrammarResult_hasChanges() {
        let noChanges = GrammarResult(
            originalText: "Hello World",
            correctedText: "Hello World",
            provider: "Claude"
        )
        XCTAssertFalse(noChanges.hasChanges)

        let hasChanges = GrammarResult(
            originalText: "Helo World",
            correctedText: "Hello World",
            provider: "Claude"
        )
        XCTAssertTrue(hasChanges.hasChanges)
    }

    func testGrammarResult_characterDelta() {
        let result = GrammarResult(
            originalText: "Helo",
            correctedText: "Hello",
            provider: "Claude"
        )
        XCTAssertEqual(result.characterDelta, 1)

        let shorterResult = GrammarResult(
            originalText: "Helllo",
            correctedText: "Hello",
            provider: "Claude"
        )
        XCTAssertEqual(shorterResult.characterDelta, -1)
    }

    // MARK: - GrammarError Tests

    func testGrammarError_errorDescriptions() {
        XCTAssertNotNil(GrammarError.noTextSelected.errorDescription)
        XCTAssertNotNil(GrammarError.textTooLong(maxLength: 1000).errorDescription)
        XCTAssertNotNil(GrammarError.accessibilityNotAvailable.errorDescription)
        XCTAssertNotNil(GrammarError.configurationInvalid("Test").errorDescription)
        XCTAssertNotNil(GrammarError.networkError("Test").errorDescription)
        XCTAssertNotNil(GrammarError.apiError("Test").errorDescription)
        XCTAssertNotNil(GrammarError.cancelled.errorDescription)
    }

    func testGrammarError_recoverySuggestions() {
        XCTAssertNotNil(GrammarError.noTextSelected.recoverySuggestion)
        XCTAssertNotNil(GrammarError.textTooLong(maxLength: 1000).recoverySuggestion)
        XCTAssertNotNil(GrammarError.accessibilityNotAvailable.recoverySuggestion)
        XCTAssertNil(GrammarError.cancelled.recoverySuggestion)
    }
}
