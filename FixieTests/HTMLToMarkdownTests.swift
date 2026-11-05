import XCTest
@testable import Fixie

final class HTMLToMarkdownTests: XCTestCase {

    private func md(_ html: String) -> String? { HTMLToMarkdown.convert(html) }

    // Regressions from the regex-based converter

    func testLineBreakNextToBold() {
        XCTAssertEqual(md("line one<br>line two <strong>bold</strong> end"), "line one\nline two **bold** end")
    }

    func testBlockquoteIsNotTreatedAsBold() {
        XCTAssertEqual(md("<blockquote>quote</blockquote><p>and <b>bold</b></p>"), "> quote\n\nand **bold**")
    }

    func testGoogleDocsWrapperIsNotBold() {
        let html = "<meta charset='utf-8'><b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\"><p><span style=\"font-weight:700\">Bold</span> text</p></b>"
        XCTAssertEqual(md(html), "**Bold** text")
    }

    func testImageIsNotTreatedAsItalic() {
        XCTAssertEqual(md("<p><img src=\"https://x/a.png\" alt=\"pic\"> text <em>it</em></p>"), "![pic](https://x/a.png) text *it*")
    }

    func testNestedLists() {
        XCTAssertEqual(md("<ul><li>parent<ul><li>child</li></ul></li><li>sibling</li></ul>"), "- parent\n  - child\n- sibling")
    }

    // Editor-specific shapes

    func testOrderedListWithParagraphsAndNesting() {
        let html = "<ol><li><p>one</p></li><li><p>two <a href=\"https://e.com\">link</a></p><ol><li>nested</li></ol></li></ol>"
        XCTAssertEqual(md(html), "1. one\n2. two [link](https://e.com)\n   1. nested")
    }

    func testTipTapTaskList() {
        let html = "<ul data-type=\"taskList\"><li data-checked=\"true\"><label><input type=\"checkbox\" checked=\"checked\"></label><div><p>done</p></div></li><li data-checked=\"false\"><label><input type=\"checkbox\"></label><div><p>todo</p></div></li></ul>"
        XCTAssertEqual(md(html), "- [x] done\n- [ ] todo")
    }

    func testQuillFlatIndentedList() {
        let html = "<ol><li data-list=\"bullet\">a</li><li data-list=\"bullet\" class=\"ql-indent-1\">b</li><li data-list=\"ordered\">c</li></ol>"
        XCTAssertEqual(md(html), "- a\n   - b\n1. c")
    }

    func testCodeBlockKeepsIndentation() {
        XCTAssertEqual(md("<pre><code>if x {\n  y()\n}</code></pre>"), "```\nif x {\n  y()\n}\n```")
    }

    func testTable() {
        XCTAssertEqual(md("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td><b>2</b></td></tr></table>"),
                       "| A | B |\n| --- | --- |\n| 1 | **2** |")
    }

    func testEmptyDivIsBlankLine() {
        XCTAssertEqual(md("<div><b>Hello</b></div><div><br></div><div>Bye</div>"), "**Hello**\n\nBye")
    }

    func testSlateZeroWidthCharactersAreDropped() {
        XCTAssertEqual(md("<p><span data-slate-zero-width=\"n\">\u{FEFF}</span><strong>x</strong></p>"), "**x**")
    }

    func testFormattingFlag() {
        XCTAssertEqual(HTMLToMarkdown.convertDetailed("<div>plain</div><div>lines</div>")?.hasFormatting, false)
        XCTAssertEqual(HTMLToMarkdown.convertDetailed("<p>a <b>b</b></p>")?.hasFormatting, true)
    }
}
