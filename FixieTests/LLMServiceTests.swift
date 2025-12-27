import XCTest
@testable import Fixie

final class LLMServiceTests: XCTestCase {

    // MARK: - Stream Parser Tests

    func testSSEStreamParser_parsesValidChunk() {
        let parser = SSEStreamParser { json in
            json["text"] as? String
        }

        let line = "data: {\"text\": \"Hello\"}"
        let result = parser.parseChunk(from: line)

        XCTAssertEqual(result, "Hello")
    }

    func testSSEStreamParser_ignoresNonDataLines() {
        let parser = SSEStreamParser { json in
            json["text"] as? String
        }

        let line = "event: message"
        let result = parser.parseChunk(from: line)

        XCTAssertNil(result)
    }

    func testSSEStreamParser_detectsDoneSignal() {
        let parser = SSEStreamParser { _ in nil }

        XCTAssertTrue(parser.isComplete(line: "data: [DONE]"))
        XCTAssertFalse(parser.isComplete(line: "data: {\"text\": \"Hello\"}"))
    }

    func testJSONLStreamParser_parsesValidChunk() {
        let parser = JSONLStreamParser(
            chunkExtractor: { json in
                json["response"] as? String
            },
            completionChecker: { json in
                json["done"] as? Bool ?? false
            }
        )

        let line = "{\"response\": \"World\", \"done\": false}"
        let result = parser.parseChunk(from: line)

        XCTAssertEqual(result, "World")
    }

    func testJSONLStreamParser_detectsCompletion() {
        let parser = JSONLStreamParser(
            chunkExtractor: { json in
                json["response"] as? String
            },
            completionChecker: { json in
                json["done"] as? Bool ?? false
            }
        )

        XCTAssertTrue(parser.isComplete(line: "{\"response\": \"\", \"done\": true}"))
        XCTAssertFalse(parser.isComplete(line: "{\"response\": \"text\", \"done\": false}"))
    }

    // MARK: - Input Sanitization Tests

    func testSanitizedForLLM_removesNullBytes() {
        let input = "Hello\0World"
        let result = input.sanitizedForLLM()

        XCTAssertEqual(result, "HelloWorld")
    }

    func testSanitizedForLLM_preservesNewlines() {
        let input = "Hello\nWorld\r\nTest"
        let result = input.sanitizedForLLM()

        XCTAssertEqual(result, "Hello\nWorld\r\nTest")
    }

    func testSanitizedForLLM_preservesTabs() {
        let input = "Hello\tWorld"
        let result = input.sanitizedForLLM()

        XCTAssertEqual(result, "Hello\tWorld")
    }

    func testSanitizedForLLM_preservesUnicode() {
        let input = "Héllo Wörld 日本語"
        let result = input.sanitizedForLLM()

        XCTAssertEqual(result, "Héllo Wörld 日本語")
    }

    func testContainsProblematicContent_detectsLongLines() {
        let longLine = String(repeating: "a", count: 10001)
        XCTAssertTrue(longLine.containsProblematicContent)

        let normalLine = String(repeating: "a", count: 1000)
        XCTAssertFalse(normalLine.containsProblematicContent)
    }
}
