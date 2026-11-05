import XCTest
import AppKit
@testable import Fixie

final class AppClassifierTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/Applications/Example.app")

    func testCatalystApp() {
        // e.g. WhatsApp (UIDeviceFamily = [6])
        XCTAssertEqual(AppClassifier.classify(bundleURL: url, infoDictionary: ["UIDeviceFamily": [6]]), .catalyst)
        XCTAssertTrue(AppClassifier.Kind.catalyst.requiresClipboardFallback)
    }

    func testIPadAppOnMac() {
        XCTAssertEqual(AppClassifier.classify(bundleURL: url, infoDictionary: ["LSRequiresIPhoneOS": true]), .catalyst)
        let wrapped = URL(fileURLWithPath: "/Applications/Game.app/Wrapper/Game.app")
        XCTAssertEqual(AppClassifier.classify(bundleURL: wrapped, infoDictionary: [:]), .catalyst)
    }

    func testBrowser() {
        let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["HTTP", "https"]]]]
        XCTAssertEqual(AppClassifier.classify(bundleURL: url, infoDictionary: info), .browser)
    }

    func testNativeApp() {
        let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["myapp"]]]]
        XCTAssertEqual(AppClassifier.classify(bundleURL: url, infoDictionary: info), .native)
        XCTAssertFalse(AppClassifier.Kind.native.requiresClipboardFallback)
    }
}

final class ClipboardManagerTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("fixie-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    private func seed() -> Data {
        let data = Data([1, 2, 3, 4])
        let item = NSPasteboardItem()
        item.setData(data, forType: .tiff)
        item.setString("copied", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return data
    }

    func testRestoresAllTypesNotJustText() {
        let image = seed()
        let manager = ClipboardManager(pasteboard: pasteboard)
        manager.saveCurrentContent()
        manager.setContent("fixed")
        manager.restoreSavedContent()
        XCTAssertEqual(pasteboard.data(forType: .tiff), image)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied")
    }

    func testRestoreWithoutSaveDoesNotWipeClipboard() {
        let image = seed()
        ClipboardManager(pasteboard: pasteboard).restoreSavedContent()
        XCTAssertEqual(pasteboard.data(forType: .tiff), image)
    }

    func testRichContentWritesHTMLAndPlainText() {
        let manager = ClipboardManager(pasteboard: pasteboard)
        manager.setContent("**bold** and [l](https://e.com)", format: .markdown(lineBased: false))
        XCTAssertEqual(pasteboard.string(forType: .string), "bold and l (https://e.com)")
        XCTAssertTrue(pasteboard.string(forType: .html)?.contains("<strong>bold</strong>") ?? false)
        XCTAssertTrue(pasteboard.types?.contains(ClipboardManager.transientType) ?? false)
    }

    func testPlainContentStaysPlain() {
        let manager = ClipboardManager(pasteboard: pasteboard)
        manager.setContent("**not markdown**", format: .plain)
        XCTAssertEqual(pasteboard.string(forType: .string), "**not markdown**")
        XCTAssertNil(pasteboard.string(forType: .html))
    }

    func testCaptureIgnoresHTMLWithoutFormatting() {
        let item = NSPasteboardItem()
        item.setString("<div>  indented</div>", forType: .html)
        item.setString("  indented", forType: .string)
        pasteboard.writeObjects([item])
        let captured = ClipboardManager(pasteboard: pasteboard).getContentPreferringMarkdown()
        XCTAssertEqual(captured?.text, "  indented")
        XCTAssertEqual(captured?.format, .plain)
    }

    func testCaptureConvertsFormattedHTML() {
        let item = NSPasteboardItem()
        item.setString("<p>Hello <b>world</b></p>", forType: .html)
        item.setString("Hello world", forType: .string)
        pasteboard.writeObjects([item])
        let captured = ClipboardManager(pasteboard: pasteboard).getContentPreferringMarkdown()
        XCTAssertEqual(captured?.text, "Hello **world**")
        XCTAssertEqual(captured?.format, .markdown(lineBased: false))
    }
}
