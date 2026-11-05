import Foundation

/// Converts clipboard HTML to markdown, preserving formatting that plain text loses.
/// Used when capturing text from Electron/web apps (Slite, Notion, Gmail, Google Docs…).
///
/// The HTML is parsed into a real tree (`XMLDocument` with libxml2's tolerant
/// HTML parser) and walked recursively, so nested lists, `<br>` next to bold
/// text, blockquotes, images, etc. no longer confuse each other the way
/// tag-matching regexes did.
enum HTMLToMarkdown {

    struct Result: Equatable {
        let markdown: String
        /// True when the HTML carried formatting that plain text can't express
        /// (bold, links, lists…). When false, the pasteboard's plain-text
        /// flavor is a more faithful source than the converted markdown.
        let hasFormatting: Bool
    }

    static func convert(_ html: String) -> String? {
        convertDetailed(html)?.markdown
    }

    static func convertDetailed(_ html: String) -> Result? {
        guard !html.isEmpty, html.utf16.count < 2_000_000 else { return nil }
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let root = document.rootElement() else { return nil }

        let body = root.elements(forName: "body").first ?? root
        var converter = Converter()
        var markdown = converter.renderContainer(body.children ?? [], style: InlineStyle(), tight: false)
        markdown = postProcess(markdown)

        guard !markdown.isEmpty else { return nil }
        return Result(markdown: markdown, hasFormatting: converter.emittedFormatting)
    }

    // MARK: - Post-processing

    private static func postProcess(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { line -> String in
            // Strip trailing whitespace (keeps leading indentation of nested lists)
            var l = line
            while let last = l.last, last == " " || last == "\t" { l.removeLast() }
            return l
        }

        // Apps that don't emit semantic lists sometimes use bullet characters.
        lines = lines.map { line in
            guard let match = line.range(of: #"^\s*[•◦▪▸►●○]\s+"#, options: .regularExpression) else { return line }
            return "- " + line[match.upperBound...]
        }

        var result = lines.joined(separator: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Converter

private struct InlineStyle {
    var bold = false
    var italic = false
    var strike = false
    var preformatted = false
}

private struct Converter {
    /// Set as soon as any markdown syntax is produced.
    var emittedFormatting = false

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "nav", "aside",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre",
        "hr", "table", "thead", "tbody", "tfoot", "tr", "figure", "figcaption",
        "dl", "dt", "dd", "address", "details", "summary",
    ]

    private static let ignoredTags: Set<String> = [
        "head", "script", "style", "meta", "title", "template", "noscript", "link",
        "svg", "button", "select", "textarea", "iframe", "object", "colgroup", "col",
    ]

    // MARK: Containers (block context)

    /// Render a sequence of sibling nodes in block context. Inline runs are
    /// grouped into paragraphs; block children are rendered and separated by
    /// a blank line (or a single newline in `tight` contexts like list items).
    mutating func renderContainer(_ nodes: [XMLNode], style: InlineStyle, tight: Bool) -> String {
        var writer = BlockWriter()
        var inline = ""

        func flushInline(_ writer: inout BlockWriter, _ inline: inout String) {
            let paragraph = Self.cleanParagraph(inline)
            if !paragraph.isEmpty {
                writer.append(paragraph, separation: 1)
            }
            inline = ""
        }

        for node in nodes {
            guard let element = node as? XMLElement else {
                inline += renderInline(node, style: style)
                continue
            }
            let tag = Self.tag(element)
            if Self.ignoredTags.contains(tag) { continue }

            if let slackType = element.attribute(forName: "data-stringify-type")?.stringValue,
               let block = renderSlackBlock(element, type: slackType, style: style) {
                flushInline(&writer, &inline)
                if !block.isEmpty { writer.append(block, separation: tight ? 1 : 2) }
                else { writer.requestSeparation(2) }
                continue
            }

            if tag == "br" {
                if element.attribute(forName: "class")?.stringValue?.contains("Apple-interchange-newline") == true { continue }
                inline += "\n"
                continue
            }

            if Self.isBlock(element) {
                flushInline(&writer, &inline)
                let separation = (tag == "div" || tight) ? 1 : 2
                let block = renderBlock(element, style: style, tight: tight)
                if !block.isEmpty {
                    writer.append(block, separation: separation)
                    if separation == 2 { writer.requestSeparation(2) }
                } else if (tag == "div" || tag == "p"), Self.isEmptyLine(element) {
                    // <div><br></div> / <p><br></p>: an intentional empty line
                    writer.requestSeparation(2)
                }
            } else if Self.containsBlock(element) {
                // Inline wrapper around blocks (e.g. Google Docs' <b id="docs-internal-guid">)
                flushInline(&writer, &inline)
                let block = renderContainer(element.children ?? [], style: applyStyle(of: element, to: style), tight: tight)
                if !block.isEmpty { writer.append(block, separation: tight ? 1 : 2) }
            } else {
                inline += renderInline(element, style: style)
            }
        }
        flushInline(&writer, &inline)
        return writer.output
    }

    private mutating func renderBlock(_ element: XMLElement, style: InlineStyle, tight: Bool) -> String {
        let tag = Self.tag(element)
        let children = element.children ?? []

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.dropFirst())) ?? 1
            let text = Self.cleanParagraph(renderInlineChildren(children, style: style))
                .replacingOccurrences(of: "\n", with: " ")
            guard !text.isEmpty else { return "" }
            emittedFormatting = true
            return String(repeating: "#", count: level) + " " + text

        case "ul", "ol":
            return renderList(element, style: style)

        case "li":
            // Orphan <li> (no list parent) — treat as bullet
            emittedFormatting = true
            return Self.prefixLines(renderContainer(children, style: style, tight: true), first: "- ", rest: "  ")

        case "blockquote":
            let inner = renderContainer(children, style: style, tight: false)
            guard !inner.isEmpty else { return "" }
            emittedFormatting = true
            return Self.prefixLines(inner, first: "> ", rest: "> ", emptyLine: ">")

        case "pre":
            return renderCodeBlock(element)

        case "hr":
            emittedFormatting = true
            return "---"

        case "table":
            return renderTable(element, style: style)

        default:
            if Self.hasPreWhitespace(element) {
                return renderCodeBlock(element)
            }
            return renderContainer(children, style: applyStyle(of: element, to: style), tight: tight)
        }
    }

    // MARK: Lists

    private mutating func renderList(_ list: XMLElement, style: InlineStyle) -> String {
        let ordered = Self.tag(list) == "ol"
        let start = Int(list.attribute(forName: "start")?.stringValue ?? "") ?? 1
        let isTaskList = list.attribute(forName: "data-type")?.stringValue == "taskList"
        var lines: [String] = []
        // Quill keeps nested lists flat: <li class="ql-indent-2">. Track
        // numbering per indentation level.
        var numbers: [Int: Int] = [:]

        for child in list.children ?? [] {
            guard let item = child as? XMLElement else { continue }
            let tag = Self.tag(item)

            // Nested list placed directly in the list (invalid but common)
            if tag == "ul" || tag == "ol" {
                let nested = renderList(item, style: style)
                if !nested.isEmpty { lines.append(Self.prefixLines(nested, first: "  ", rest: "  ")) }
                continue
            }
            guard tag == "li" else { continue }

            let level = Self.quillIndent(item)
            numbers = numbers.filter { $0.key <= level }
            func nextNumber() -> Int {
                let n = numbers[level].map { $0 + 1 } ?? (level == 0 ? start : 1)
                numbers[level] = n
                return n
            }

            // Quill renders every list as <ol> and stores the real type per item.
            let dataList = item.attribute(forName: "data-list")?.stringValue
            var marker: String
            switch dataList {
            case "bullet": marker = "- "
            case "ordered": marker = "\(nextNumber()). "
            case "checked": marker = "- [x] "
            case "unchecked": marker = "- [ ] "
            default:
                if let checked = Self.taskState(item, inTaskList: isTaskList) {
                    marker = checked ? "- [x] " : "- [ ] "
                } else if ordered {
                    marker = "\(nextNumber()). "
                } else {
                    marker = "- "
                }
            }

            let content = renderContainer(Self.itemChildren(item), style: style, tight: true)
            let indent = String(repeating: " ", count: marker.hasPrefix("- [") ? 2 : marker.count)
            let levelIndent = String(repeating: "   ", count: level)
            if content.isEmpty {
                lines.append(levelIndent + marker.trimmingCharacters(in: .whitespaces))
            } else {
                lines.append(Self.prefixLines(content, first: levelIndent + marker, rest: levelIndent + indent))
            }
        }

        guard !lines.isEmpty else { return "" }
        emittedFormatting = true
        return lines.joined(separator: "\n")
    }

    /// Children of a list item, minus the checkbox UI of task lists.
    private static func itemChildren(_ item: XMLElement) -> [XMLNode] {
        (item.children ?? []).filter { node in
            guard let el = node as? XMLElement else { return true }
            let tag = tag(el)
            if tag == "input" { return false }
            // TipTap: <label><input type=checkbox><span></span></label>
            if tag == "label", el.elements(forName: "input").isEmpty == false { return false }
            return true
        }
    }

    /// Detect checklist items across editors: TipTap (`data-checked`),
    /// Lexical (`aria-checked`), plain `<input type=checkbox>`.
    private static func taskState(_ item: XMLElement, inTaskList: Bool) -> Bool? {
        if let checked = item.attribute(forName: "data-checked")?.stringValue {
            return checked == "true"
        }
        if item.attribute(forName: "role")?.stringValue == "checkbox",
           let aria = item.attribute(forName: "aria-checked")?.stringValue {
            return aria == "true"
        }
        if let input = firstDescendant(of: item, maxDepth: 3, where: {
            tag($0) == "input" && $0.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox"
        }) {
            return input.attribute(forName: "checked") != nil
        }
        return inTaskList ? false : nil
    }

    // MARK: Code

    private mutating func renderCodeBlock(_ element: XMLElement) -> String {
        var code = Self.rawText(element)
        while code.hasSuffix("\n") { code.removeLast() }
        while code.hasPrefix("\n") { code.removeFirst() }
        guard !code.isEmpty else { return "" }
        emittedFormatting = true
        let fence = code.contains("```") ? "~~~" : "```"
        return fence + "\n" + code + "\n" + fence
    }

    // MARK: Tables

    private mutating func renderTable(_ table: XMLElement, style: InlineStyle) -> String {
        var rows: [[String]] = []
        Self.forEachDescendant(of: table) { el in
            guard Self.tag(el) == "tr" else { return true }
            let cells = (el.children ?? []).compactMap { $0 as? XMLElement }
                .filter { ["td", "th"].contains(Self.tag($0)) }
                .map { cell -> String in
                    var inner = Converter()
                    let text = inner.renderContainer(cell.children ?? [], style: style, tight: true)
                    return text.replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "|", with: "\\|")
                        .trimmingCharacters(in: .whitespaces)
                }
            if !cells.isEmpty { rows.append(cells) }
            return false
        }
        guard let header = rows.first else { return "" }
        let width = rows.map(\.count).max() ?? header.count
        func line(_ cells: [String]) -> String {
            let padded = cells + Array(repeating: "", count: max(0, width - cells.count))
            return "| " + padded.joined(separator: " | ") + " |"
        }
        emittedFormatting = true
        var out = [line(header), "|" + Array(repeating: " --- |", count: width).joined()]
        out += rows.dropFirst().map(line)
        return out.joined(separator: "\n")
    }

    // MARK: Slack rendered messages

    /// Slack's message view annotates elements with `data-stringify-type`.
    private mutating func renderSlackBlock(_ element: XMLElement, type: String, style: InlineStyle) -> String? {
        switch type {
        case "paragraph-break":
            return ""
        case "pre":
            return renderCodeBlock(element)
        case "blockquote":
            let inner = renderContainer(element.children ?? [], style: style, tight: false)
            emittedFormatting = true
            return Self.prefixLines(inner, first: "> ", rest: "> ", emptyLine: ">")
        case "unordered-list-item":
            emittedFormatting = true
            return "- " + Self.cleanParagraph(renderInlineChildren(element.children ?? [], style: style))
        case "ordered-list-item":
            emittedFormatting = true
            return "1. " + Self.cleanParagraph(renderInlineChildren(element.children ?? [], style: style))
        default:
            return nil
        }
    }

    // MARK: Inline

    private mutating func renderInlineChildren(_ nodes: [XMLNode], style: InlineStyle) -> String {
        nodes.map { renderInline($0, style: style) }.joined()
    }

    private mutating func renderInline(_ node: XMLNode, style: InlineStyle) -> String {
        switch node.kind {
        case .text:
            let raw = node.stringValue ?? ""
            if style.preformatted { return raw }
            return Self.collapseWhitespace(raw)
        case .element:
            break
        default:
            return ""
        }
        guard let element = node as? XMLElement else { return "" }
        let tag = Self.tag(element)
        if Self.ignoredTags.contains(tag) { return "" }
        let children = element.children ?? []

        switch tag {
        case "br":
            if element.attribute(forName: "class")?.stringValue?.contains("Apple-interchange-newline") == true { return "" }
            return "\n"

        case "code", "kbd", "samp", "tt":
            let code = Self.collapseWhitespace(Self.rawText(element))
            guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return code }
            emittedFormatting = true
            let fence = code.contains("`") ? "``" : "`"
            let pad = code.contains("`") ? " " : ""
            return fence + pad + code + pad + fence

        case "a":
            let text = renderInlineChildren(children, style: style)
            let href = element.attribute(forName: "href")?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
            // Slack mentions/channels: keep the visible text only
            if element.attribute(forName: "data-stringify-type")?.stringValue == "mention" { return text }
            guard !href.isEmpty, !href.lowercased().hasPrefix("javascript:"), !href.hasPrefix("#") else { return text }
            let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty || label == href || "mailto:" + label == href {
                return label.isEmpty ? href : text
            }
            emittedFormatting = true
            return Self.moveWhitespaceOutside(text) { "[\($0)](\(href))" }

        case "img":
            guard let src = element.attribute(forName: "src")?.stringValue,
                  src.hasPrefix("http") else { return "" }
            let alt = element.attribute(forName: "alt")?.stringValue ?? ""
            emittedFormatting = true
            return "![\(alt)](\(src))"

        case "input":
            if element.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" {
                emittedFormatting = true
                return element.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
            }
            return ""

        default:
            let newStyle = applyStyle(of: element, to: style)
            let inner = renderInlineChildren(children, style: newStyle)
            return wrap(inner, from: style, to: newStyle)
        }
    }

    /// Wrap `text` with the emphasis markers that `to` adds on top of `from`.
    private mutating func wrap(_ text: String, from: InlineStyle, to: InlineStyle) -> String {
        var markers = ""
        if to.bold && !from.bold { markers += "**" }
        if to.italic && !from.italic { markers += "*" }
        if to.strike && !from.strike { markers = "~~" + markers }
        guard !markers.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        emittedFormatting = true
        let closing = String(markers.reversed())
        // Multi-line emphasis isn't valid markdown — apply it per line.
        let lines = text.components(separatedBy: "\n")
        return lines.map { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty
                ? line
                : Self.moveWhitespaceOutside(line) { markers + $0 + closing }
        }.joined(separator: "\n")
    }

    /// Compute the inline style an element applies (tag semantics + inline CSS).
    private func applyStyle(of element: XMLElement, to style: InlineStyle) -> InlineStyle {
        var s = style
        let tag = Self.tag(element)
        let css = (element.attribute(forName: "style")?.stringValue ?? "").lowercased()
            .replacingOccurrences(of: " ", with: "")

        switch tag {
        case "b", "strong": s.bold = true
        case "em", "i", "cite", "var", "dfn": s.italic = true
        case "s", "del", "strike": s.strike = true
        default: break
        }

        if let weight = Self.cssValue("font-weight", in: css) {
            let numeric = Int(weight)
            if weight == "bold" || weight == "bolder" || (numeric ?? 0) >= 600 {
                s.bold = true
            } else if weight == "normal" || weight == "lighter" || (numeric ?? 600) < 600 {
                // Google Docs wraps the whole selection in <b style="font-weight:normal">
                s.bold = false
            }
        }
        if let fontStyle = Self.cssValue("font-style", in: css) {
            if fontStyle == "italic" || fontStyle == "oblique" { s.italic = true }
            if fontStyle == "normal" { s.italic = false }
        }
        if let deco = Self.cssValue("text-decoration", in: css) ?? Self.cssValue("text-decoration-line", in: css),
           deco.contains("line-through") {
            s.strike = true
        }
        return s
    }

    // MARK: Helpers

    /// `<li class="ql-indent-2">` → 2
    static func quillIndent(_ element: XMLElement) -> Int {
        guard let cls = element.attribute(forName: "class")?.stringValue,
              let range = cls.range(of: #"ql-indent-(\d+)"#, options: .regularExpression) else { return 0 }
        return Int(cls[range].dropFirst("ql-indent-".count)) ?? 0
    }

    /// An element with no text, only line breaks (`<div><br></div>`).
    static func isEmptyLine(_ element: XMLElement) -> Bool {
        var hasBreak = false
        var hasOther = false
        forEachDescendant(of: element) { el in
            if tag(el) == "br" { hasBreak = true } else if ["img", "input", "hr"].contains(tag(el)) { hasOther = true }
            return true
        }
        let text = (element.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return hasBreak && !hasOther && text.isEmpty
    }

    static func tag(_ element: XMLElement) -> String {
        (element.localName ?? element.name ?? "").lowercased()
    }

    static func isBlock(_ element: XMLElement) -> Bool {
        blockTags.contains(tag(element))
    }

    static func containsBlock(_ element: XMLElement) -> Bool {
        var found = false
        forEachDescendant(of: element) { el in
            if isBlock(el) { found = true }
            return !found
        }
        return found
    }

    static func hasPreWhitespace(_ element: XMLElement) -> Bool {
        let css = (element.attribute(forName: "style")?.stringValue ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        return css.contains("white-space:pre") && !css.contains("white-space:pre-line")
    }

    static func cssValue(_ property: String, in css: String) -> String? {
        for declaration in css.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0] == property {
                return parts[1].replacingOccurrences(of: "!important", with: "")
            }
        }
        return nil
    }

    /// Depth-first walk; the visitor returns false to skip an element's subtree.
    static func forEachDescendant(of element: XMLElement, _ visit: (XMLElement) -> Bool) {
        for child in element.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            if visit(el) { forEachDescendant(of: el, visit) }
        }
    }

    static func firstDescendant(of element: XMLElement, maxDepth: Int, where predicate: (XMLElement) -> Bool) -> XMLElement? {
        guard maxDepth > 0 else { return nil }
        for child in element.children ?? [] {
            guard let el = child as? XMLElement else { continue }
            if tag(el) == "ul" || tag(el) == "ol" { continue }
            if predicate(el) { return el }
            if let found = firstDescendant(of: el, maxDepth: maxDepth - 1, where: predicate) { return found }
        }
        return nil
    }

    /// Text content preserving newlines (`<br>` and block boundaries).
    static func rawText(_ node: XMLNode) -> String {
        if node.kind == .text { return node.stringValue ?? "" }
        guard let el = node as? XMLElement else { return "" }
        let tag = tag(el)
        if tag == "br" { return "\n" }
        var text = (el.children ?? []).map(rawText).joined()
        if ["div", "p", "li", "tr"].contains(tag), !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            // Zero-width characters editors use as cursor anchors (Slate, Lexical…)
            if scalar == "\u{FEFF}" || scalar == "\u{200B}" { continue }
            if scalar == " " || scalar == "\n" || scalar == "\t" || scalar == "\r" || scalar == "\u{00A0}" {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Trim each line of an inline run and drop surrounding blank lines.
    static func cleanParagraph(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    /// `**  bold **` isn't valid markdown: keep the spaces outside the markers.
    static func moveWhitespaceOutside(_ text: String, _ transform: (String) -> String) -> String {
        let leading = text.prefix { $0 == " " }
        let trailing = text.reversed().prefix { $0 == " " }
        let core = text.trimmingCharacters(in: .whitespaces)
        return String(leading) + transform(core) + String(trailing)
    }

    static func prefixLines(_ text: String, first: String, rest: String, emptyLine: String? = nil) -> String {
        text.components(separatedBy: "\n").enumerated().map { index, line in
            if index == 0 { return first + line }
            if line.isEmpty { return emptyLine ?? "" }
            return rest + line
        }.joined(separator: "\n")
    }
}

/// Accumulates blocks with the right number of newlines between them.
private struct BlockWriter {
    private(set) var output = ""
    private var pendingSeparation = 0

    mutating func requestSeparation(_ n: Int) {
        if !output.isEmpty { pendingSeparation = max(pendingSeparation, n) }
    }

    mutating func append(_ block: String, separation: Int) {
        if !output.isEmpty {
            let n = max(pendingSeparation, separation)
            output += String(repeating: "\n", count: n)
        }
        output += block
        pendingSeparation = 0
    }
}
