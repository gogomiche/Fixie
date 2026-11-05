import Foundation

/// Converts the markdown Fixie works with back into rich clipboard flavors.
///
/// When text is captured from a rich editor (Slack, Slite, Notion…) Fixie
/// turns its HTML into markdown so the LLM can preserve the formatting. On
/// the way back we must undo that conversion, otherwise the editor receives
/// literal `**bold**` and `- item` text. This produces:
/// - `html(from:)`: an HTML fragment for `public.html` (rich editors)
/// - `plainText(from:)`: the same text without markdown syntax (plain fields)
///
/// It handles the subset Fixie itself emits: headings, paragraphs with hard
/// line breaks, nested bullet/ordered/task lists, blockquotes, fenced code,
/// horizontal rules, tables, bold/italic/strike/inline code, links and images.
enum MarkdownToHTML {

    /// - Parameter preserveBlankLines: line-based editors (Slack's composer)
    ///   treat every newline as meaningful, so a blank line between two
    ///   paragraphs must become an explicit empty paragraph. Block editors
    ///   (Slite, Notion, Docs) already space paragraphs, so leave it off.
    static func html(from markdown: String, preserveBlankLines: Bool = false) -> String {
        let blocks = BlockParser.parse(markdown, keepAllBlankLines: preserveBlankLines)
        return "<meta charset=\"utf-8\">" + blocks.map(renderHTML).joined()
    }

    static func plainText(from markdown: String) -> String {
        let blocks = BlockParser.parse(markdown)
        return blocks.map { renderPlain($0) }.joined(separator: "\n\n")
    }

    // MARK: - HTML rendering

    private static func renderHTML(_ block: MDBlock) -> String {
        switch block {
        case .paragraph(let text):
            // Each blank-line-separated paragraph → <p>; single newlines → <br>.
            return "<p>" + Inline.html(text).replacingOccurrences(of: "\n", with: "<br>") + "</p>"
        case .blank:
            return "<p><br></p>"
        case .heading(let level, let text):
            return "<h\(level)>" + Inline.html(text) + "</h\(level)>"
        case .code(let language, let code):
            let cls = language.map { " class=\"language-\(escape($0))\"" } ?? ""
            return "<pre><code\(cls)>" + escape(code) + "</code></pre>"
        case .quote(let inner):
            return "<blockquote>" + inner.map(renderHTML).joined() + "</blockquote>"
        case .hr:
            return "<hr>"
        case .list(let ordered, let start, let items):
            let isTaskList = items.contains { $0.task != nil }
            let tag = ordered ? "ol" : "ul"
            let startAttr = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let typeAttr = isTaskList ? " data-type=\"taskList\"" : ""
            let lis = items.map { item -> String in
                var attrs = ""
                var checkbox = ""
                if let checked = item.task {
                    attrs = " data-type=\"taskItem\" data-checked=\"\(checked)\""
                    checkbox = "<input type=\"checkbox\"\(checked ? " checked" : "") disabled> "
                }
                return "<li\(attrs)>" + checkbox + renderListItemContent(item.blocks) + "</li>"
            }
            return "<\(tag)\(startAttr)\(typeAttr)>" + lis.joined() + "</\(tag)>"
        case .table(let header, let rows):
            let head = "<thead><tr>" + header.map { "<th>" + Inline.html($0) + "</th>" }.joined() + "</tr></thead>"
            let body = rows.map { row in
                "<tr>" + row.map { "<td>" + Inline.html($0) + "</td>" }.joined() + "</tr>"
            }.joined()
            return "<table>" + head + "<tbody>" + body + "</tbody></table>"
        }
    }

    /// Tight list items: render a leading paragraph inline (no <p>) so
    /// editors don't insert extra spacing inside lists.
    private static func renderListItemContent(_ blocks: [MDBlock]) -> String {
        var out = ""
        for (index, block) in blocks.enumerated() {
            if index == 0, case .paragraph(let text) = block {
                out += Inline.html(text).replacingOccurrences(of: "\n", with: "<br>")
            } else if case .blank = block {
                continue
            } else {
                out += renderHTML(block)
            }
        }
        return out
    }

    // MARK: - Plain-text rendering

    private static func renderPlain(_ block: MDBlock, depth: Int = 0) -> String {
        switch block {
        case .paragraph(let text):
            return Inline.plain(text)
        case .blank:
            return ""
        case .heading(_, let text):
            return Inline.plain(text)
        case .code(_, let code):
            return code
        case .quote(let inner):
            return inner.map { renderPlain($0) }.joined(separator: "\n\n")
                .components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        case .hr:
            return "---"
        case .list(let ordered, let start, let items):
            return items.enumerated().map { index, item -> String in
                var marker = ordered ? "\(start + index). " : "- "
                if let checked = item.task { marker = checked ? "☑ " : "☐ " }
                let content = item.blocks.filter { if case .blank = $0 { return false }; return true }
                    .map { renderPlain($0) }.joined(separator: "\n")
                let indent = String(repeating: " ", count: marker.count)
                return content.components(separatedBy: "\n").enumerated()
                    .map { $0.offset == 0 ? marker + $0.element : indent + $0.element }
                    .joined(separator: "\n")
            }.joined(separator: "\n")
        case .table(let header, let rows):
            return ([header] + rows).map { $0.map(Inline.plain).joined(separator: "\t") }.joined(separator: "\n")
        }
    }

    fileprivate static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}

// MARK: - Block model

private indirect enum MDBlock {
    case paragraph(String)
    /// An extra empty line beyond a normal paragraph break (chat apps keep them).
    case blank
    case heading(Int, String)
    case code(String?, String)
    case quote([MDBlock])
    case list(ordered: Bool, start: Int, items: [MDListItem])
    case hr
    case table(header: [String], rows: [[String]])
}

private struct MDListItem {
    var task: Bool?
    var blocks: [MDBlock]
}

// MARK: - Block parser

private enum BlockParser {

    static func parse(_ markdown: String, keepAllBlankLines: Bool = false) -> [MDBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
        return parseLines(normalized.components(separatedBy: "\n"), keepAllBlankLines: keepAllBlankLines)
    }

    private static func parseLines(_ lines: [String], keepAllBlankLines: Bool = false) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var paragraph: [String] = []
        var blankRun = 0
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                blankRun += 1
                i += 1
                continue
            }
            // Blank lines beyond a normal paragraph break are kept as empty
            // paragraphs (all of them for line-based editors).
            let extraBlanks = keepAllBlankLines ? blankRun : blankRun - 1
            if extraBlanks > 0, !blocks.isEmpty {
                blocks.append(contentsOf: Array(repeating: .blank, count: extraBlanks))
            }
            blankRun = 0

            // Fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // closing fence
                blocks.append(.code(language.isEmpty ? nil : language, code.joined(separator: "\n")))
                continue
            }

            // Heading
            if let heading = matchHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(heading.0, heading.1))
                i += 1
                continue
            }

            // Horizontal rule (before lists: "- - -" / "***")
            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.hr)
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = t.dropFirst()
                    if content.hasPrefix(" ") { content = content.dropFirst() }
                    quoted.append(String(content))
                    i += 1
                }
                blocks.append(.quote(parseLines(quoted, keepAllBlankLines: keepAllBlankLines)))
                continue
            }

            // Table
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("|") else { break }
                    rows.append(tableCells(t))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // List
            if listMarker(line) != nil, paragraph.isEmpty || startsListAfterParagraph(line) {
                flushParagraph()
                let (list, next) = parseList(lines, from: i, keepAllBlankLines: keepAllBlankLines)
                blocks.append(list)
                i = next
                continue
            }

            paragraph.append(line.trimmingCharacters(in: .whitespaces))
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: Lists

    struct Marker {
        let indent: Int
        let ordered: Bool
        let number: Int
        let width: Int      // marker + following space
        let content: String
    }

    static func listMarker(_ line: String) -> Marker? {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }

        if first == "-" || first == "*" || first == "+" {
            let after = rest.dropFirst()
            guard after.first == " " else { return nil }
            return Marker(indent: indent, ordered: false, number: 0, width: 2,
                          content: String(after.dropFirst()))
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let afterDigits = rest.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")",
              afterDigits.dropFirst().first == " " else { return nil }
        return Marker(indent: indent, ordered: true, number: Int(digits) ?? 1,
                      width: digits.count + 2, content: String(afterDigits.dropFirst(2)))
    }

    /// Like CommonMark: inside a paragraph only "- " or "1. " may start a list.
    private static func startsListAfterParagraph(_ line: String) -> Bool {
        guard let m = listMarker(line) else { return false }
        return !m.content.isEmpty && (!m.ordered || m.number == 1)
    }

    private static func parseList(_ lines: [String], from start: Int, keepAllBlankLines: Bool) -> (MDBlock, Int) {
        guard let first = listMarker(lines[start]) else { return (.paragraph(lines[start]), start + 1) }
        var items: [MDListItem] = []
        var i = start

        while i < lines.count, let marker = listMarker(lines[i]),
              marker.indent == first.indent, marker.ordered == first.ordered {
            var content = marker.content
            var task: Bool?
            if content.hasPrefix("[ ] ") || content == "[ ]" {
                task = false; content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if content.lowercased().hasPrefix("[x] ") || content.lowercased() == "[x]" {
                task = true; content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }

            var itemLines = [content]
            let contentColumn = marker.indent + marker.width
            i += 1

            while i < lines.count {
                let line = lines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let indent = line.prefix { $0 == " " }.count

                if trimmed.isEmpty {
                    // Blank line: continue the item only if indented content follows
                    if i + 1 < lines.count {
                        let next = lines[i + 1]
                        let nextIndent = next.prefix { $0 == " " }.count
                        if !next.trimmingCharacters(in: .whitespaces).isEmpty, nextIndent > marker.indent {
                            itemLines.append("")
                            i += 1
                            continue
                        }
                    }
                    break
                }
                if indent > marker.indent {
                    itemLines.append(String(line.dropFirst(min(indent, contentColumn))))
                    i += 1
                    continue
                }
                if listMarker(line) != nil || isHorizontalRule(trimmed) || trimmed.hasPrefix(">")
                    || trimmed.hasPrefix("```") || matchHeading(trimmed) != nil {
                    break
                }
                // Lazy continuation of the item's paragraph
                itemLines.append(trimmed)
                i += 1
            }
            items.append(MDListItem(task: task, blocks: parseLines(itemLines, keepAllBlankLines: keepAllBlankLines)))

            // Blank line between items of the same list
            if i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
               i + 1 < lines.count, let next = listMarker(lines[i + 1]),
               next.indent == first.indent, next.ordered == first.ordered {
                i += 1
            }
        }
        return (.list(ordered: first.ordered, start: first.number, items: items), i)
    }

    // MARK: Other blocks

    private static func matchHeading(_ trimmed: String) -> (Int, String)? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let ch = compact.first, "-*_".contains(ch) else { return false }
        return compact.allSatisfy { $0 == ch }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in t {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; current.append(ch); continue }
            if ch == "|" { cells.append(current); current = ""; continue }
            current.append(ch)
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|") }
    }
}

// MARK: - Inline parser

private enum Inline {

    enum Node {
        case text(String)
        case code(String)
        case strong([Node])
        case emphasis([Node])
        case strike([Node])
        case link(text: [Node], url: String)
        case image(alt: String, url: String)
    }

    static func html(_ text: String) -> String {
        render(parse(Array(text)), html: true)
    }

    static func plain(_ text: String) -> String {
        render(parse(Array(text)), html: false)
    }

    private static func render(_ nodes: [Node], html: Bool) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let t):
                return html ? MarkdownToHTML.escape(t) : t
            case .code(let c):
                return html ? "<code>" + MarkdownToHTML.escape(c) + "</code>" : c
            case .strong(let inner):
                return html ? "<strong>" + render(inner, html: true) + "</strong>" : render(inner, html: false)
            case .emphasis(let inner):
                return html ? "<em>" + render(inner, html: true) + "</em>" : render(inner, html: false)
            case .strike(let inner):
                return html ? "<del>" + render(inner, html: true) + "</del>" : render(inner, html: false)
            case .link(let inner, let url):
                let label = render(inner, html: html)
                if html {
                    return "<a href=\"" + MarkdownToHTML.escape(url) + "\">" + label + "</a>"
                }
                return label == url ? url : label + " (" + url + ")"
            case .image(let alt, let url):
                return html
                    ? "<img src=\"" + MarkdownToHTML.escape(url) + "\" alt=\"" + MarkdownToHTML.escape(alt) + "\">"
                    : (alt.isEmpty ? url : alt)
            }
        }.joined()
    }

    private static func parse(_ chars: [Character]) -> [Node] {
        var nodes: [Node] = []
        var buffer = ""
        var i = 0

        func flush() {
            if !buffer.isEmpty { nodes.append(.text(buffer)); buffer = "" }
        }

        while i < chars.count {
            let c = chars[i]

            // Backslash escape
            if c == "\\", i + 1 < chars.count, "\\`*_~[]()#+-.!|>".contains(chars[i + 1]) {
                buffer.append(chars[i + 1])
                i += 2
                continue
            }

            // Inline code
            if c == "`" {
                let run = countRun(chars, from: i, of: "`")
                if let close = findCodeClose(chars, from: i + run, run: run) {
                    flush()
                    var code = String(chars[(i + run)..<close])
                    if run > 1, code.hasPrefix(" "), code.hasSuffix(" "), code.count >= 2 {
                        code = String(code.dropFirst().dropLast())
                    }
                    nodes.append(.code(code))
                    i = close + run
                    continue
                }
            }

            // Image / link
            if c == "!" , i + 1 < chars.count, chars[i + 1] == "[",
               let (label, url, end) = parseLinkTail(chars, openBracket: i + 1) {
                flush()
                nodes.append(.image(alt: String(label), url: url))
                i = end
                continue
            }
            if c == "[", let (label, url, end) = parseLinkTail(chars, openBracket: i) {
                flush()
                nodes.append(.link(text: parse(label), url: url))
                i = end
                continue
            }

            // Emphasis / strike
            if c == "*" || c == "_" || c == "~" {
                let run = countRun(chars, from: i, of: c)
                if let (node, end) = parseDelimited(chars, at: i, char: c, run: run) {
                    flush()
                    nodes.append(node)
                    i = end
                    continue
                }
                buffer += String(repeating: c, count: run)
                i += run
                continue
            }

            buffer.append(c)
            i += 1
        }
        flush()
        return nodes
    }

    private static func countRun(_ chars: [Character], from i: Int, of c: Character) -> Int {
        var n = 0
        while i + n < chars.count, chars[i + n] == c { n += 1 }
        return n
    }

    private static func findCodeClose(_ chars: [Character], from start: Int, run: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                let r = countRun(chars, from: j, of: "`")
                if r == run { return j }
                j += r
            } else {
                j += 1
            }
        }
        return nil
    }

    /// `[label](url)` starting at `openBracket`. Returns label chars, url, index after ")".
    private static func parseLinkTail(_ chars: [Character], openBracket: Int) -> ([Character], String, Int)? {
        var depth = 0
        var j = openBracket
        var closeBracket: Int?
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "[" { depth += 1 }
            if chars[j] == "]" {
                depth -= 1
                if depth == 0 { closeBracket = j; break }
            }
            j += 1
        }
        guard let cb = closeBracket, cb + 1 < chars.count, chars[cb + 1] == "(" else { return nil }
        var k = cb + 2
        var parens = 1
        var url = ""
        while k < chars.count {
            if chars[k] == "(" { parens += 1 }
            if chars[k] == ")" {
                parens -= 1
                if parens == 0 { break }
            }
            if chars[k] == "\n" { return nil }
            url.append(chars[k])
            k += 1
        }
        guard k < chars.count, !url.isEmpty, !url.contains(" ") || url.hasPrefix("<") else { return nil }
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        return (Array(chars[(openBracket + 1)..<cb]), url, k + 1)
    }

    /// Parse `**strong**`, `*em*`, `_em_`, `__strong__`, `~~strike~~`, `~strike~`.
    private static func parseDelimited(_ chars: [Character], at i: Int, char c: Character, run: Int) -> (Node, Int)? {
        // Only handle runs of 1–3; `***x***` = strong + em.
        guard run <= 3 else { return nil }
        if c == "~" && run > 2 { return nil }

        let open = i + run
        guard open < chars.count, !chars[open].isWhitespace else { return nil }
        // `_` inside words (snake_case) is not emphasis.
        if c == "_", i > 0, chars[i - 1].isLetter || chars[i - 1].isNumber { return nil }

        var j = open
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "`" {
                // Skip code spans inside emphasis
                let r = countRun(chars, from: j, of: "`")
                if let close = findCodeClose(chars, from: j + r, run: r) { j = close + r; continue }
            }
            if chars[j] == "\n", j + 1 < chars.count, chars[j + 1] == "\n" { return nil }
            if chars[j] == c {
                let r = countRun(chars, from: j, of: c)
                let prevIsSpace = chars[j - 1].isWhitespace
                let followedByWord = c == "_" && j + r < chars.count && (chars[j + r].isLetter || chars[j + r].isNumber)
                // A nested opener of a different length (`*a **b** c*`): skip its pair.
                if r != run, j + r < chars.count, !chars[j + r].isWhitespace, prevIsSpace,
                   let (_, nestedEnd) = parseDelimited(chars, at: j, char: c, run: r) {
                    j = nestedEnd
                    continue
                }
                if r >= run, !prevIsSpace, !followedByWord, j > open {
                    let inner = Array(chars[open..<j])
                    let end = j + run
                    switch (c, run) {
                    case ("~", _): return (.strike(parse(inner)), end)
                    case (_, 1): return (.emphasis(parse(inner)), end)
                    case (_, 2): return (.strong(parse(inner)), end)
                    default: return (.strong([.emphasis(parse(inner))]), end)
                    }
                }
                j += r
                continue
            }
            j += 1
        }
        return nil
    }
}
