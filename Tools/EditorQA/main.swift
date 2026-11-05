import Cocoa
import WebKit

// Fixie editor QA harness.
//
// Drives real web editors (Quill, ProseMirror/TipTap, Slate, Lexical,
// CKEditor, bare contenteditable, textarea) in a WKWebView and replays what
// Fixie does: copy the selection → convert to markdown → (LLM) → write the
// clipboard → paste. Compares the previous implementation ("avant") with the
// current one ("après"). Also checks app classification and clipboard
// save/restore. Run with Tools/EditorQA/run.sh.

// MARK: - Reference document

let referenceMarkdown = """
## Compte rendu

Salut **l'équipe**, voici le *récap* de la réunion avec un [lien](https://example.com).

- Point **important**
- Deuxième point
  - Sous-point

1. Première étape
2. Deuxième étape

> Une citation à garder

On garde le `code inline` et le texte ~~barré~~.

```
let x = 1
```

- [x] Tâche faite
- [ ] Tâche à faire
"""

struct Feature { let name: String; let pattern: String }

let features: [Feature] = [
    .init(name: "Titre", pattern: #"(?m)^#{1,6} Compte rendu"#),
    .init(name: "Gras", pattern: #"\*\*l'équipe\*\*"#),
    .init(name: "Italique", pattern: #"(?<![*\w])[*_]récap[*_](?![*\w])"#),
    .init(name: "Lien", pattern: #"\[lien\]\(https://example\.com/?\)"#),
    .init(name: "Puces", pattern: #"(?m)^- Point"#),
    .init(name: "Sous-liste", pattern: #"(?m)^ {2,}- Sous-point"#),
    .init(name: "Liste num.", pattern: #"(?m)^1\. Première étape\n2\. Deuxième étape"#),
    .init(name: "Citation", pattern: #"(?m)^> Une citation"#),
    .init(name: "Code", pattern: "`code inline`"),
    .init(name: "Barré", pattern: #"~~barré~~"#),
    .init(name: "Bloc code", pattern: "```[a-z]*\\nlet x = 1\\n```"),
    .init(name: "Tâches", pattern: #"(?m)^- \[x\] Tâche faite\n- \[ \] Tâche à faire"#),
]

/// Markdown syntax that should never be visible to the user after a paste.
let leakPatterns = [#"\*\*"#, #"\]\(http"#, "~~", "```", #"(?m)^#{1,6} "#, #"(?m)^> "#]

func matches(_ pattern: String, _ text: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

func presentFeatures(_ markdown: String) -> Set<String> {
    Set(features.filter { matches($0.pattern, markdown) }.map(\.name))
}

func leaks(_ visibleText: String) -> Int {
    leakPatterns.filter { matches($0, visibleText) }.count
}

// MARK: - Editors

struct EditorPage { let file: String; let name: String; let models: String }

let editors: [EditorPage] = [
    .init(file: "quill1", name: "Quill 1.3", models: "Slack (composer basé sur Quill)"),
    .init(file: "quill2", name: "Quill 2", models: "Slack, apps Quill récentes"),
    .init(file: "slate", name: "Slate", models: "Slite"),
    .init(file: "tiptap", name: "TipTap / ProseMirror", models: "éditeurs de docs par blocs"),
    .init(file: "lexical", name: "Lexical", models: "WhatsApp Web, apps Meta"),
    .init(file: "ckeditor5", name: "CKEditor 5", models: "CMS, outils de support"),
    .init(file: "contenteditable", name: "contenteditable brut", models: "webmails, formulaires riches"),
    .init(file: "textarea", name: "textarea", models: "champs texte simples"),
]

// MARK: - WebView driver

@MainActor
final class Driver: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    let pagesDir: URL

    init(pagesDir: URL) {
        self.pagesDir = pagesDir
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), configuration: config)
        window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1000, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(webView)
    }

    func load(_ page: EditorPage) async throws {
        let common = try String(contentsOf: pagesDir.appendingPathComponent("common.js"), encoding: .utf8)
        var html = try String(contentsOf: pagesDir.appendingPathComponent(page.file + ".html"), encoding: .utf8)
        html = html.replacingOccurrences(of: "/*QA-COMMON*/", with: common)
        webView.loadHTMLString(html, baseURL: URL(string: "https://fixie-qa.localhost/")!)
        for _ in 0..<300 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let state = try? await js("return window.QAReady === true ? 'ready' : (window.QAError || '')")
            if state == "ready" { return }
            if let s = state, !s.isEmpty { throw NSError(domain: "QA", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
        }
        throw NSError(domain: "QA", code: 2, userInfo: [NSLocalizedDescriptionKey: "timeout loading \(page.file)"])
    }

    @discardableResult
    func js(_ body: String, _ args: [String: Any] = [:]) async throws -> String {
        let result = try await webView.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page)
        if let s = result as? String { return s }
        return result.map { "\($0)" } ?? ""
    }

    func setHTML(_ html: String) async throws {
        try await js("await QA.setHTML(html); await QAUtil.sleep(300); return 'ok'", ["html": html])
    }

    func editorHTML() async throws -> String { try await js("return await QA.getHTML()") }
    func editorText() async throws -> String { try await js("return await QA.getText()") }

    func copyAll() async throws -> (html: String, text: String, source: String) {
        let json = try await js("return JSON.stringify(await QA.copyAll())")
        let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        return (obj["html"] as? String ?? "", obj["text"] as? String ?? "", obj["source"] as? String ?? "")
    }

    func paste(_ flavors: [String: String]) async throws -> String {
        try await js("return (await QA.paste(data)).handledBy", ["data": flavors])
    }
}

// MARK: - Fixie behaviours under test

enum Version { case before, after }

/// What Fixie reads from the clipboard after ⌘C.
func capture(html: String, plain: String, version: Version) -> (markdown: String, format: TextFormat) {
    switch version {
    case .before:
        if !html.isEmpty, let md = LegacyHTMLToMarkdown.convert(html) { return (md, .plain) }
        return (plain, .plain)
    case .after:
        if !html.isEmpty, let r = HTMLToMarkdown.convertDetailed(html), r.hasFormatting {
            return (r.markdown, .markdown(lineBased: false))
        }
        return (plain, .plain)
    }
}

/// The clipboard flavors Fixie writes before pasting.
func flavors(for text: String, format: TextFormat, version: Version) -> [String: String] {
    switch (version, format) {
    case (.before, _), (.after, .plain):
        return ["text/plain": text]
    case (.after, .markdown(let lineBased)):
        return ["text/html": MarkdownToHTML.html(from: text, preserveBlankLines: lineBased),
                "text/plain": MarkdownToHTML.plainText(from: text)]
    }
}

// MARK: - Report

var report: [String] = []
func log(_ line: String = "") { print(line); report.append(line) }

func cell(_ got: Set<String>, of capability: Set<String>, leaks: Int) -> String {
    let ok = got.intersection(capability).count
    let leakText = leaks > 0 ? " · ⚠️ \(leaks) balise(s) visibles" : ""
    let mark = ok == capability.count && leaks == 0 ? "✅" : (ok * 2 >= capability.count && leaks == 0 ? "🟡" : "❌")
    return "\(mark) \(ok)/\(capability.count)\(leakText)"
}

@MainActor
func runWebEditors(pagesDir: URL) async {
    let driver = Driver(pagesDir: pagesDir)
    let referenceHTML = MarkdownToHTML.html(from: referenceMarkdown)

    log("## 1. Éditeurs web — aller-retour complet (copie → Fixie → collage)")
    log("")
    log("Texte de référence avec 12 éléments de mise en forme. « Capacité » = ce que l'éditeur sait représenter. Le LLM est simulé par l'identité (texte renvoyé tel quel) pour isoler la mise en forme.")
    log("")
    log("| Éditeur | Modèle de | Capacité | Lecture avant | Lecture après | Aller-retour avant | Aller-retour après |")
    log("|---|---|---|---|---|---|---|")

    var details: [String] = []

    for page in editors {
        do {
            try await driver.load(page)

            // Capability: what survives the editor's own HTML import.
            try await driver.setHTML(referenceHTML)
            let capability = presentFeatures(HTMLToMarkdown.convert(try await driver.editorHTML()) ?? "")
                .union(page.file == "textarea" ? [] : [])

            // Read: copy from the editor and convert.
            let copied = try await driver.copyAll()
            var readCells: [Version: String] = [:]
            var captured: [Version: (String, TextFormat)] = [:]
            for v in [Version.before, .after] {
                let c = capture(html: copied.html, plain: copied.text, version: v)
                captured[v] = (c.markdown, c.format)
                readCells[v] = cell(presentFeatures(c.markdown), of: capability, leaks: 0)
            }

            // Full round-trip: paste what Fixie would write back.
            var tripCells: [Version: String] = [:]
            for v in [Version.before, .after] {
                guard let (md, format) = captured[v] else { continue }
                let handledBy = try await driver.paste(flavors(for: md, format: format, version: v))
                let resultMD = HTMLToMarkdown.convert(try await driver.editorHTML()) ?? ""
                let visible = try await driver.editorText()
                tripCells[v] = cell(presentFeatures(resultMD), of: capability, leaks: leaks(visible))
                let missing = capability.subtracting(presentFeatures(resultMD)).sorted()
                details.append("- **\(page.name)** \(v == .before ? "avant" : "après") — collage géré par `\(handledBy)`, copie via `\(copied.source)`"
                    + (missing.isEmpty ? "" : ", perdu : \(missing.joined(separator: ", "))")
                    + (leaks(visible) > 0 ? ", balises visibles dans le texte" : ""))
            }

            let capText = capability.count == features.count ? "12/12" : "\(capability.count)/12"
            log("| \(page.name) | \(page.models) | \(capText) | \(readCells[.before]!) | \(readCells[.after]!) | \(tripCells[.before]!) | \(tripCells[.after]!) |")
        } catch {
            log("| \(page.name) | \(page.models) | ⛔️ erreur : \(error.localizedDescription.prefix(120)) | | | | |")
        }
    }
    log("")
    log("<details><summary>Détail par éditeur</summary>")
    log("")
    details.forEach { log($0) }
    log("")
    log("</details>")
    log("")

    // Slack-specific: blank lines between paragraphs (Slack's Quill delta source).
    log("## 2. Slack — lignes vides entre paragraphes")
    log("")
    let slackMD = "Salut **toi**\n\nLigne après une ligne vide\n- un point"
    log("| Éditeur | HTML « blocs » (Slite, Notion…) | HTML « lignes » (source Slack) |")
    log("|---|---|---|")
    for file in ["quill1", "quill2"] {
        guard let page = editors.first(where: { $0.file == file }) else { continue }
        do {
            try await driver.load(page)
            var cells: [String] = []
            for lineBased in [false, true] {
                _ = try await driver.paste(flavors(for: slackMD, format: .markdown(lineBased: lineBased), version: .after))
                let text = try await driver.editorText()
                let kept = text.contains("Salut toi\n\nLigne après")
                cells.append(kept ? "✅ ligne vide conservée" : "❌ ligne vide perdue")
            }
            log("| \(page.name) | \(cells[0]) | \(cells[1]) |")
        } catch {
            log("| \(page.name) | ⛔️ \(error.localizedDescription) | |")
        }
    }
    log("")
}

// MARK: - Slack clipboard (Quill delta inside Chromium web-custom-data)

func chromiumCustomData(_ entries: [(String, String)]) -> Data {
    // Chromium Pickle: [u32 payload size][u32 count] then (string16 type, string16 value)*
    var payload = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; payload.append(Data(bytes: &x, count: 4)) }
    func string16(_ s: String) {
        let units = Array(s.utf16)
        u32(UInt32(units.count))
        for u in units { var x = u.littleEndian; payload.append(Data(bytes: &x, count: 2)) }
        if (units.count * 2) % 4 != 0 { payload.append(contentsOf: [0, 0]) }
    }
    u32(UInt32(entries.count))
    for (t, v) in entries { string16(t); string16(v) }
    var out = Data()
    var size = UInt32(payload.count).littleEndian
    out.append(Data(bytes: &size, count: 4))
    out.append(payload)
    return out
}

func runSlackDelta() {
    log("## 3. Slack — format presse-papier natif (Quill Delta)")
    log("")
    let delta = #"{"ops":[{"insert":"Salut "},{"insert":"l'équipe","attributes":{"bold":true}},{"insert":" "},{"insert":{"slackemoji":{"text":":wave:"}}},{"insert":"\n\nPoint un"},{"insert":"\n","attributes":{"list":"bullet"}},{"insert":"Sous-point"},{"insert":"\n","attributes":{"list":"bullet","indent":1}},{"insert":"let a = 1"},{"insert":"\n","attributes":{"code-block":true}},{"insert":"let b = 2"},{"insert":"\n","attributes":{"code-block":true}},{"insert":"Merci "},{"insert":{"slackuser":{"id":"U123","name":"hugo"}}},{"insert":"\n"}]}"#
    let pb = NSPasteboard(name: NSPasteboard.Name("fixie-qa-slack-\(UUID().uuidString)"))
    pb.clearContents()
    let item = NSPasteboardItem()
    item.setData(chromiumCustomData([("slack/texty", delta)]), forType: ClipboardManager.chromiumCustomDataType)
    item.setString("Salut l'équipe :wave:\n\nPoint un\nSous-point\nlet a = 1\nlet b = 2\nMerci @hugo", forType: .string)
    pb.writeObjects([item])

    let manager = ClipboardManager(pasteboard: pb)
    let captured = manager.getContentPreferringMarkdown()
    let md = captured?.text ?? ""
    let checks: [(String, Bool)] = [
        ("gras", md.contains("**l'équipe**")),
        ("emoji", md.contains(":wave:")),
        ("ligne vide", md.contains(":wave:\n\n- Point un")),
        ("sous-liste", md.contains("\n  - Sous-point")),
        ("bloc de code multi-ligne (1 seul bloc)", md.contains("```\nlet a = 1\nlet b = 2\n```")),
        ("mention conservée", md.contains("@hugo")),
        ("format « lignes » détecté", captured?.format == .markdown(lineBased: true)),
    ]
    for (name, ok) in checks { log("- \(ok ? "✅" : "❌") \(name)") }
    let legacy = LegacyQuillDeltaParser.toMarkdown(delta) ?? ""
    log("")
    log("Avant : `\(legacy.replacingOccurrences(of: "\n", with: "⏎"))`  ")
    log("Après : `\(md.replacingOccurrences(of: "\n", with: "⏎"))`")
    log("")
}

// MARK: - App classification

func runClassification() {
    log("## 4. Détection du type d'app (choix AX vs presse-papier)")
    log("")
    log("| App | Avant | Après | Chemin d'écriture après |")
    log("|---|---|---|---|")
    let apps = ["/Applications/WhatsApp.app", "/Applications/Slack.app", "/Applications/Dia.app",
                "/Applications/Safari.app", "/System/Applications/TextEdit.app", "/System/Applications/Notes.app",
                "/System/Applications/Mail.app", "/System/Applications/Messages.app"]
    for path in apps {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let info = Bundle(url: url)?.infoDictionary ?? [:]
        let before = AppClassifier.isElectron(bundleURL: url) || AppClassifier.isBrowser(infoDictionary: info)
        let kind = AppClassifier.classify(bundleURL: url)
        log("| \(url.deletingPathExtension().lastPathComponent) | \(before ? "presse-papier" : "AX") | \(kind.rawValue) | \(kind.requiresClipboardFallback ? "presse-papier + ⌘V" : "AX (vérifié, repli ⌘V)") |")
    }

    // False positives: native AppKit apps must stay native.
    var catalyst: [String] = []
    var total = 0
    for dir in ["/Applications", "/System/Applications"] {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".app") {
            total += 1
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if AppClassifier.classify(bundleURL: url) == .catalyst { catalyst.append(name.replacingOccurrences(of: ".app", with: "")) }
        }
    }
    log("")
    log("Sur les \(total) apps installées, détectées Catalyst/iPad : \(catalyst.sorted().joined(separator: ", ")).")
    log("")
}

// MARK: - Clipboard save/restore

func runClipboard() {
    log("## 5. Presse-papier de l'utilisateur")
    log("")
    let pb = NSPasteboard(name: NSPasteboard.Name("fixie-qa-clip-\(UUID().uuidString)"))
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
    let tiff = image.tiffRepresentation!

    func seed() {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(tiff, forType: .tiff)
        item.setString("texte copié", forType: .string)
        pb.writeObjects([item])
    }

    // Clipboard path: save → Fixie writes → restore
    seed()
    let m = ClipboardManager(pasteboard: pb)
    m.saveCurrentContent()
    m.setContent("**x**", format: .markdown(lineBased: false))
    let wroteHTML = pb.string(forType: .html)?.contains("<strong>x</strong>") == true
    let transient = pb.types?.contains(ClipboardManager.transientType) == true
    m.restoreSavedContent()
    let imageBack = pb.data(forType: .tiff) == tiff
    let textBack = pb.string(forType: .string) == "texte copié"

    // AX path: nothing saved → restore must not wipe the clipboard
    seed()
    let m2 = ClipboardManager(pasteboard: pb)
    m2.restoreSavedContent()
    let untouched = pb.data(forType: .tiff) == tiff

    log("- \(wroteHTML ? "✅" : "❌") Fixie écrit du HTML + texte brut quand la source est riche")
    log("- \(transient ? "✅" : "❌") Écriture marquée transitoire (ignorée par Raycast/Alfred/Paste)")
    log("- \(imageBack ? "✅" : "❌") Une image copiée par l'utilisateur est restaurée (avant : perdue, seul le texte était sauvegardé)")
    log("- \(textBack ? "✅" : "❌") Le texte copié par l'utilisateur est restauré")
    log("- \(untouched ? "✅" : "❌") Chemin Accessibilité : le presse-papier n'est plus vidé (avant : `restoreSavedContent()` le vidait)")
    log("")
}

// MARK: - Main

let args = CommandLine.arguments
let pagesDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "Tools/EditorQA/pages")
let reportPath = args.count > 2 ? args[2] : nil

NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    log("# Fixie — QA mise en forme par type d'éditeur")
    log("")
    await runWebEditors(pagesDir: pagesDir)
    runSlackDelta()
    runClassification()
    runClipboard()
    if let path = reportPath {
        try? report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
    exit(0)
}
NSApplication.shared.run()
