import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativePanTests {
    @Test
    @MainActor
    func nativeButtonsCrossLoadedCoverageWithoutMovingRowsOrOverwritingNewerScroll() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 500 { await gate.pause(250) }
            return records
        })
        try await files.openedSession(fixture: "rows", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let buttons = workspace.subviews.compactMap { $0 as? NSButton }
        let left = try #require(buttons.first { $0.accessibilityLabel() == "Pan left" })
        let right = try #require(buttons.first { $0.accessibilityLabel() == "Pan right" })
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:101-200")
        await session.submitInterval()?.value
        workspace.layoutSubtreeIfNeeded()
        let original = session.presentation.alignments
        #expect(original.count == 80)
        let height = stack.frame.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        right.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:151-250")
        let pending = session.submitInterval()
        await gate.waitFor(250)
        #expect(!spinner.isHidden)
        #expect(left.isEnabled && right.isEnabled, "Navigation remains available during loading")
        #expect(session.presentation.alignments == original)
        #expect(scroll.contentView.bounds.origin.y == 200)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        await gate.release(250)
        await pending?.value
        #expect(spinner.isHidden)
        #expect(session.presentation.alignments == original)
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(stack.frame.height == height)
        left.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:101-200")
        #expect(spinner.isHidden)
        #expect(session.presentation.alignments == original)
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(stack.frame.height == height)

        session.editInterval("tiny:101-101")
        #expect(session.submitInterval() == nil)
        right.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:102-102")
        #expect(session.presentation.alignments == original)
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(stack.frame.height == height)

        let alert = NSAlert()
        alert.messageText = "Modal navigation check"
        alert.addButton(withTitle: "OK")
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { _ in continuation.resume() }
            right.performClick(nil)
            #expect(session.presentation.target?.formatted == "tiny:102-102")
            window.endSheet(alert.window)
        }

    }

    @Test
    @MainActor
    func nativePanButtonsNavigateReferenceEndsAndReplaceOnlyChangedDrafts() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .disabled)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let buttons = workspace.subviews.compactMap { $0 as? NSButton }
        let left = try #require(buttons.first { $0.accessibilityLabel() == "Pan left" })
        let right = try #require(buttons.first { $0.accessibilityLabel() == "Pan right" })
        #expect(!left.isEnabled && !right.isEnabled)
        try await files.openedSession(session: session)
        #expect(!left.isEnabled && !right.isEnabled)
        session.editInterval("tiny:2-11")
        await session.submitInterval()?.value
        #expect(left.isEnabled && right.isEnabled)
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("tiny:2-1", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(session.presentation.intervalError != nil)
        left.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:1-10")
        #expect(field.stringValue == "tiny:1-10")
        #expect(editor.string == "tiny:1-10")
        #expect(session.presentation.intervalError == nil)
        await session.submitInterval()?.value
        #expect(!left.isEnabled && right.isEnabled)
        session.editInterval("rejected draft")
        session.submitInterval()
        let error = session.presentation.intervalError
        left.performClick(nil)
        #expect(field.stringValue == "rejected draft")
        #expect(session.presentation.intervalError == error)
        right.performClick(nil)
        #expect(field.stringValue == "tiny:6-15")
        await session.submitInterval()?.value

        session.editInterval("tiny:1990-1999")
        await session.submitInterval()?.value
        right.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:1,991-2,000")
        #expect(left.isEnabled && !right.isEnabled)
        await session.submitInterval()?.value
        workspace.layoutSubtreeIfNeeded()
        let ruler = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Genomic ruler" })
        let labels = ruler.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("tiny:1,991-2,000"))
        #expect(left.frame.maxX <= right.frame.minX)
        #expect(right.frame.maxX < field.frame.minX)
        #expect(workspace.bounds.contains(left.frame) && workspace.bounds.contains(right.frame))
    }
}
