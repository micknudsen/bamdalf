import AppKit
import BamdalfKit
import Testing

@MainActor
@Suite(.serialized)
struct NativeStandaloneReferenceTests {
    @Test(arguments: [false, true]) func fileMenuBrowsesAndClosesWithAReadOnlyFieldAtBothWindowWidths(longName: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let name = longName ? String(repeating: "long assembly ", count: 9) + "/ α.bref" : "GRCh38.bref"
        let url = try files.reference("different-filename.bref", name: name, fasta: ">seq\naCGtn")
        let session = ViewerSession()
        let (opened, signal) = AsyncStream<Void>.makeStream()
        let controller = ViewerWindowController(session: session) { panel, _, choose in
            #expect(panel is NSOpenPanel && panel.allowedContentTypes.first?.preferredFilenameExtension == "bref")
            choose(url)
        }
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let menu = controller.makeFileMenu()
        let open = try #require(menu.item(withTitle: "Open Reference…"))
        let close = try #require(menu.item(withTitle: "Close Reference"))
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Selected reference" })
        #expect(field.stringValue == "No reference" && !field.isHidden && !field.isEditable)
        #expect(field.bezelStyle == .roundedBezel)
        #expect(field.subviews.contains { $0 is NSImageView })
        #expect(controller.validateMenuItem(open) && !controller.validateMenuItem(close))
        let render = session.onPresentationChange
        session.onPresentationChange = {
            render?()
            if session.presentation.referenceURL == url && !session.presentation.isOpening { signal.yield() }
        }
        menu.performActionForItem(at: menu.index(of: open))
        var events = opened.makeAsyncIterator()
        _ = await events.next()
        session.onPresentationChange = render
        #expect(controller.validateMenuItem(close))
        let entry = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        for width in [1100, 640] {
            window.setContentSize(NSSize(width: width, height: 480))
            workspace.layoutSubtreeIfNeeded()
            #expect(workspace.bounds.width == CGFloat(width))
            #expect(field.stringValue == name && field.toolTip == url.lastPathComponent)
            #expect(entry.frame.maxX < field.frame.minX && workspace.bounds.contains(field.frame))
            #expect(field.frame.height == entry.frame.height && field.frame.width >= 100)
            #expect((field.intrinsicContentSize.width > field.frame.width) == longName)
            #expect(field.lineBreakMode == .byTruncatingTail)
        }
        session.editInterval("seq:1-5")
        await session.submitInterval()?.value
        session.editInterval("retain this draft")
        let before = session.presentation
        await session.openReference(files.directory.appendingPathComponent("missing.bref"))
        #expect(session.presentation.openError != nil)
        #expect(field.stringValue == name && field.toolTip == url.lastPathComponent)
        #expect(session.presentation.referenceURL == url && session.presentation.target == before.target)
        #expect(session.presentation.referenceBases == before.referenceBases)
        #expect(session.presentation.intervalText == "retain this draft")
        menu.performActionForItem(at: menu.index(of: close))
        #expect(field.stringValue == "No reference" && !field.isHidden)
        #expect(entry.isHidden && session.presentation.referenceURL == nil)
    }
}

extension NativeStandaloneReferenceTests {
    @Test(arguments: [false, true]) func nativeRowKeepsItsCoordinatesCaseAndScale(dark: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("hg.bref", fasta: ">one\nAaCGtn" + String(repeating: "G", count: 620))
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 640, height: 480))
        let workspace = try #require(window.contentView)
        workspace.layoutSubtreeIfNeeded()
        await session.openReference(url)
        let row = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Reference sequence" })
        let ruler = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Genomic ruler" })
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        session.editInterval("one:1-76")
        await session.submitInterval()?.value
        try #require(row.bounds.width == 608)
        #expect(!row.isHidden && row.frame.maxY <= ruler.frame.minY)
        #expect(row.frame.minY >= scroll.frame.maxY && row.frame.minX == ruler.frame.minX)
        let fixed = row.convert(row.bounds, to: nil)
        session.scrollVertically(to: 30)
        #expect(scroll.contentView.bounds.origin.y == 30)
        #expect(row.convert(row.bounds, to: nil) == fixed)
        let letters = try renderAlignmentBitmap(in: row, window: window)
        var glyphDifferences = 0
        for x in 0..<8 {
            for y in 3..<15 where letters.colorAt(x: x, y: y) != letters.colorAt(x: x + 8, y: y) {
                glyphDifferences += 1
            }
        }
        #expect(glyphDifferences > 0, "Uppercase A and lowercase a have different glyphs at eight points")
        session.editInterval("one:1-77")
        await session.submitInterval()?.value
        let cells = try renderAlignmentBitmap(in: row, window: window)
        let green = try #require(cells.colorAt(x: 4, y: 8)?.usingColorSpace(.deviceRGB))
        #expect(green.greenComponent > green.redComponent && green.greenComponent > green.blueComponent)
        #expect(cells.colorAt(x: 4, y: 8) == cells.colorAt(x: 12, y: 8))
        #expect((4..<14).allSatisfy { cells.colorAt(x: 4, y: $0) == cells.colorAt(x: 4, y: 8) })
        #expect(cells.colorAt(x: 12, y: 8) != cells.colorAt(x: 17, y: 8))
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.4 / 77)?.value
        let dragged = try renderAlignmentBitmap(in: row, window: window)
        #expect(dragged.colorAt(x: 14, y: 8) == cells.colorAt(x: 17, y: 8), "Fractional motion moves the leading edge of C")
        await session.endAlignmentDrag()?.value
        session.editInterval("one:1-608")
        await session.submitInterval()?.value
        let unit = try renderAlignmentBitmap(in: row, window: window)
        #expect(unit.colorAt(x: 0, y: 8) == unit.colorAt(x: 1, y: 8))
        #expect(unit.colorAt(x: 1, y: 8) != unit.colorAt(x: 2, y: 8))
        session.editInterval("one:1-609")
        await session.submitInterval()?.value
        let blank = try renderAlignmentBitmap(in: row, window: window)
        #expect(blank.colorAt(x: 1, y: 8) == blank.colorAt(x: 2, y: 8))
        #expect(session.presentation.referenceBases == nil && row.convert(row.bounds, to: nil) == fixed)
    }
}

extension NativeStandaloneReferenceTests {
    @Test func selectionAfterSaveApprovalStillProtectsTheDestination() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let output = try files.reference("selected.bref", fasta: ">seq\nacgt")
        let alias = files.directory.appendingPathComponent("alias.bref")
        try FileManager.default.linkItem(at: output, to: alias)
        let source = files.directory.appendingPathComponent("new.fa")
        try Data(">new\nA".utf8).write(to: source)
        let original = try Data(contentsOf: output)
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        defer { controller.window?.close() }
        controller.createReference(nil)
        let form = try creationForm(controller)
        defer { form.close() }
        let approval = try ReferenceSaveDestination(confirmedURL: alias)
        await session.openReference(output)
        let saving = controller.referenceCreation.saveReference(from: source, name: "replacement", to: approval)
        #expect(saving == nil)
        await saving?.value
        #expect((try textField("Creation error", in: form)).stringValue.contains("open reference"))
        #expect(try Data(contentsOf: output) == original)
        #expect(try Data(contentsOf: alias) == original)
        #expect(session.presentation.referenceURL == output)
    }

    @Test(.timeLimit(.minutes(1))) func createCommandProtectsTheOpenBundleThroughAHardLink() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("selected.bref", fasta: ">seq\nacgt")
        let alias = files.directory.appendingPathComponent("alias.bref")
        try FileManager.default.linkItem(at: url, to: alias)
        let source = files.directory.appendingPathComponent("new.fa")
        try Data(">new\nA".utf8).write(to: source)
        let original = try Data(contentsOf: url)
        let session = ViewerSession()
        await session.openReference(url)
        let (validated, signal) = AsyncStream<Void>.makeStream()
        let controller = ViewerWindowController(session: session) { panel, _, complete in
            if panel is NSOpenPanel {
                complete(source)
            } else {
                if let approval = panel.delegate as? ReferenceSaveApproval {
                    #expect(throws: (any Error).self) { try approval.panel(panel, validate: alias) }
                } else {
                    Issue.record("Missing Save approval")
                }
                complete(nil)
                signal.yield()
            }
        }
        let menu = controller.makeFileMenu()
        let create = try #require(menu.item(withTitle: "Create Reference…"))
        menu.performActionForItem(at: menu.index(of: create))
        let form = try creationForm(controller)
        defer { form.close() }
        click(try button("Browse…", in: form))
        click(try button("Create bundle", in: form))
        var events = validated.makeAsyncIterator()
        _ = await events.next()
        #expect(session.presentation.referenceURL == url)
        #expect(try Data(contentsOf: alias) == original)
    }
}
