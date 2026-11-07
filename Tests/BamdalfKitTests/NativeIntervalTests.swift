import AppKit
import Testing
import BamdalfKit

struct NativeIntervalTests {
    @Test
    @MainActor
    func nativeRulerDisplaysTheTargetIndependentlyOfDraftsAndResizesItsLabels() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        await session.openBAM(files.sources.appendingPathComponent("coordinates.bam"))
        await session.chooseIndex(files.sources.appendingPathComponent("coordinates.bam.csi"))
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let content = try #require(window.contentView)
        session.editInterval("large_reference:1-300000000")
        session.submitInterval()
        content.layoutSubtreeIfNeeded()
        let ruler = try #require(content.subviews.first { $0.accessibilityLabel() == "Genomic ruler" })
        let labels = ruler.subviews.compactMap { $0 as? NSTextField }
        #expect(labels.contains { $0.stringValue == "large_reference:1-300,000,000" })
        #expect(labels.contains { $0.stringValue == "150,000,000" })
        let tickLabels = labels.filter { !$0.stringValue.contains(":") }
        for pair in zip(tickLabels, tickLabels.dropFirst()) {
            #expect(pair.0.frame.maxX < pair.1.frame.minX)
        }
        #expect(labels.allSatisfy { ruler.bounds.contains($0.frame) })
        let image = try #require(ruler.bitmapImageRepForCachingDisplay(in: ruler.bounds))
        ruler.cacheDisplay(in: ruler.bounds, to: image)
        #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
        session.editInterval("unsubmitted draft")
        content.layoutSubtreeIfNeeded()
        let draftLabels = ruler.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(draftLabels.contains("large_reference:1-300,000,000"))
        window.setContentSize(NSSize(width: 640, height: 400))
        content.layoutSubtreeIfNeeded()
        let narrowLabels = ruler.subviews.compactMap { $0 as? NSTextField }
        #expect(narrowLabels.count < labels.count)
        #expect(narrowLabels.allSatisfy { ruler.bounds.contains($0.frame) })
        session.editInterval("large_reference:150000000-150000000")
        session.submitInterval()
        content.layoutSubtreeIfNeeded()
        let singleLabels = ruler.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(singleLabels.contains("150,000,000"))
        try captureNativeWindow(window, name: "one-base")
    }

    @Test
    @MainActor
    func goCommandSelectsUnchangedTextAndEscapeResetsOnlyTheActiveEditor() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let menu = controller.makeGoMenu()
        let command = try #require(menu.items.first)
        #expect(menu.title == "Go")
        #expect(command.title == "Go to Interval")
        #expect(command.keyEquivalent == "l")
        #expect(command.keyEquivalentModifierMask == .command)
        menu.update()
        #expect(!command.isEnabled)

        await session.openBAM(files.sources.appendingPathComponent("opening.bam"))
        await session.chooseIndex(files.sources.appendingPathComponent("opening.bam.bai"))
        let field = try #require(window.contentView?.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        session.editInterval("tiny:2-1")
        session.submitInterval()
        let error = session.presentation.intervalError
        window.makeFirstResponder(nil)
        menu.update()
        #expect(command.isEnabled)
        menu.performActionForItem(at: 0)
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 8))
        #expect(session.presentation.intervalText == "tiny:2-1")
        #expect(session.presentation.intervalError == error)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(session.presentation.intervalError == error)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(session.presentation.intervalText == "")
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.target == nil)

        editor.insertText("tiny:100-100", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("draft", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(field.stringValue == "tiny:100-100")
        #expect(session.presentation.target?.formatted == "tiny:100-100")

        let alert = NSAlert()
        alert.messageText = "Native modal check"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
        defer { window.endSheet(alert.window) }
        menu.update()
        #expect(!command.isEnabled)
        #expect(!controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(window.attachedSheet === alert.window)
    }

    @Test(arguments: ["valid", "out-of-range", "malformed", "editing"])
    @MainActor
    func nativeEditorSubmitsOnEnterAndRetainsRejectedDraftOnFocusLoss(example: String) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        await session.openBAM(files.sources.appendingPathComponent("opening.bam"))
        await session.chooseIndex(files.sources.appendingPathComponent("opening.bam.bai"))
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let content = try #require(window.contentView)
        let field = try #require(content.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("tiny:1000-2000", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(field.stringValue == "tiny:1,000-2,000")
        #expect(session.presentation.target?.formatted == "tiny:1,000-2,000")
        if example == "valid" {
            try captureNativeWindow(window, name: example)
            return
        }

        editor.insertText("tiny:2001-2002", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        #expect(session.presentation.intervalError == nil)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        let error = try #require(content.subviews.compactMap { $0 as? NSTextField }.first {
            $0.stringValue == "End must not exceed 2,000 for tiny."
        })
        #expect(!error.isHidden)
        content.layoutSubtreeIfNeeded()
        #expect(error.frame.maxY <= field.frame.minY)
        window.makeFirstResponder(nil)
        #expect(field.stringValue == "tiny:2001-2002")
        #expect(session.presentation.intervalError != nil)
        #expect(session.presentation.target?.formatted == "tiny:1,000-2,000")
        if example == "out-of-range" {
            try captureNativeWindow(window, name: example)
            return
        }
        window.makeFirstResponder(field)
        let resumedEditor = try #require(field.currentEditor() as? NSTextView)
        resumedEditor.insertText("tiny:10,00-2,000", replacementRange: NSRange(location: 0, length: resumedEditor.string.utf16.count))
        resumedEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(session.presentation.intervalError != nil)
        #expect(session.presentation.target?.formatted == "tiny:1,000-2,000")
        if example == "malformed" {
            try captureNativeWindow(window, name: example)
            return
        }
        resumedEditor.insertText("tiny:", replacementRange: NSRange(location: 0, length: resumedEditor.string.utf16.count))
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.target?.formatted == "tiny:1,000-2,000")
        try captureNativeWindow(window, name: example)
    }
}

/// Optional visual evidence from the same native window exercised by the tests.
@MainActor
private func captureNativeWindow(_ window: NSWindow, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["BAMDALF_NATIVE_CAPTURES"] else { return }
    let content = try #require(window.contentView)
    content.layoutSubtreeIfNeeded()
    CATransaction.flush()
    let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(content.bounds.width), pixelsHigh: Int(content.bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: image))
    content.displayIgnoringOpacity(content.bounds, in: context)
    let png = try #require(image.representation(using: .png, properties: [:]))
    let output = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try png.write(to: output.appendingPathComponent("\(name).png"))
}
