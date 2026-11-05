import XCTest
@testable import Fixie

final class MarkdownToHTMLTests: XCTestCase {

    private func html(_ md: String, lineBased: Bool = false) -> String {
        MarkdownToHTML.html(from: md, preserveBlankLines: lineBased)
            .replacingOccurrences(of: "<meta charset=\"utf-8\">", with: "")
    }

    func testInlineFormatting() {
        XCTAssertEqual(html("Salut **l'équipe**, *récap* ~~barré~~ `code` [lien](https://e.com)"),
                       "<p>Salut <strong>l'équipe</strong>, <em>récap</em> <del>barré</del> <code>code</code> <a href=\"https://e.com\">lien</a></p>")
    }

    func testNestedEmphasis() {
        XCTAssertEqual(html("*a **b** c*"), "<p><em>a <strong>b</strong> c</em></p>")
        XCTAssertEqual(html("***x***"), "<p><strong><em>x</em></strong></p>")
    }

    func testSnakeCaseIsNotItalic() {
        XCTAssertEqual(html("use snake_case_name here"), "<p>use snake_case_name here</p>")
    }

    func testHTMLIsEscaped() {
        XCTAssertEqual(html("a < b & <script>"), "<p>a &lt; b &amp; &lt;script&gt;</p>")
    }

    func testLists() {
        XCTAssertEqual(html("- a\n  - b\n- c\n\n1. one\n2. two"),
                       "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul><ol><li>one</li><li>two</li></ol>")
    }

    func testTaskList() {
        XCTAssertTrue(html("- [x] done").contains("data-checked=\"true\""))
    }

    func testQuoteCodeHeadingRule() {
        XCTAssertEqual(html("## T\n\n> q\n\n```\nx < 1\n```\n\n---"),
                       "<h2>T</h2><blockquote><p>q</p></blockquote><pre><code>x &lt; 1</code></pre><hr>")
    }

    func testLineBreaksAndBlankLines() {
        XCTAssertEqual(html("a\nb\n\nc"), "<p>a<br>b</p><p>c</p>")
        // Slack: every blank line is meaningful
        XCTAssertEqual(html("a\n\nc", lineBased: true), "<p>a</p><p><br></p><p>c</p>")
    }

    func testPlainText() {
        XCTAssertEqual(MarkdownToHTML.plainText(from: "## T\n\n**b** [l](https://e.com)\n\n- x\n  - y"),
                       "T\n\nb l (https://e.com)\n\n- x\n  - y")
    }

    func testRoundTripThroughHTMLToMarkdown() {
        let md = "## Titre\n\nSalut **toi**, un [lien](https://e.com).\n\n- a\n  - b\n\n1. un\n2. deux\n\n> cite\n\n```\nlet x = 1\n```"
        XCTAssertEqual(HTMLToMarkdown.convert(MarkdownToHTML.html(from: md)), md)
    }
}
