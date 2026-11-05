import XCTest
@testable import Fixie

final class QuillDeltaParserTests: XCTestCase {

    func testFormattingListsCodeAndEmbeds() {
        let delta = #"{"ops":[{"insert":"Hi "},{"insert":"team","attributes":{"bold":true}},{"insert":" "},{"insert":{"slackemoji":{"text":":wave:"}}},{"insert":"\n\nOne"},{"insert":"\n","attributes":{"list":"bullet"}},{"insert":"Sub"},{"insert":"\n","attributes":{"list":"bullet","indent":1}},{"insert":"let a = 1"},{"insert":"\n","attributes":{"code-block":true}},{"insert":"let b = 2"},{"insert":"\n","attributes":{"code-block":true}},{"insert":"Ping "},{"insert":{"slackuser":{"id":"U1","name":"hugo"}}},{"insert":"\n"}]}"#
        XCTAssertEqual(QuillDeltaParser.toMarkdown(delta),
                       "Hi **team** :wave:\n\n- One\n  - Sub\n```\nlet a = 1\nlet b = 2\n```\nPing @hugo")
    }

    func testOrderedNumberingPerLevel() {
        let delta = #"{"ops":[{"insert":"a"},{"insert":"\n","attributes":{"list":"ordered"}},{"insert":"a1"},{"insert":"\n","attributes":{"list":"ordered","indent":1}},{"insert":"b"},{"insert":"\n","attributes":{"list":"ordered"}}]}"#
        XCTAssertEqual(QuillDeltaParser.toMarkdown(delta), "1. a\n  1. a1\n2. b")
    }

    func testBoldSpacesStayOutsideMarkers() {
        let delta = #"{"ops":[{"insert":"a"},{"insert":" bold ","attributes":{"bold":true}},{"insert":"b\n"}]}"#
        XCTAssertEqual(QuillDeltaParser.toMarkdown(delta), "a **bold** b")
    }

    func testExtractIgnoresBracesInsideStrings() {
        let json = #"{"ops":[{"insert":"a } b {\n"}]}"#
        var data = Data([0, 0, 0, 0])
        data.append(json.data(using: .utf16LittleEndian)!)
        XCTAssertEqual(QuillDeltaParser.extractSlackJSON(from: data), json)
    }
}
