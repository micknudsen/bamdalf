import AppKit
import BamdalfKit
import Testing

@Suite(.serialized)
@MainActor
struct NativeReferenceSaveTests {
    @Test(arguments: [false, true])
    func savingAReferenceReturnsToTheSameViewer(withBAM: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .disabled)
        if withBAM {
            try await files.openedSession(fixture: "rows", session: session)
            session.editInterval("tiny:101-200")
            await session.submitInterval()?.value
            session.editInterval("newer draft")
        }
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let before = session.presentation
        let input = files.directory.appendingPathComponent("tiny.fa")
        let output = files.directory.appendingPathComponent("tiny.bref")
        try Data(">chr\ngTA".utf8).write(to: input)
        let approved = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(controller.saveReference(from: input, to: approved))
        let progressSheet = try #require(window.attachedSheet)
        #expect(progressSheet.title == "Creating Reference")
        controller.panRight(nil)
        #expect(session.presentation.target == before.target)
        await saving.value

        #expect(window.attachedSheet == nil)
        #expect(session.presentation.bamURL == before.bamURL)
        #expect(session.presentation.sessionID == before.sessionID)
        #expect(session.presentation.intervalText == before.intervalText)
        #expect(session.presentation.target == before.target)
        #expect(session.presentation.alignments == before.alignments)
        #expect(session.presentation.verticalOffset == before.verticalOffset)
        #expect(window.title == before.windowTitle)
        let bundle = try ReferenceBundle(opening: output)
        #expect(try await bundle.read(GenomicInterval(reference: "chr", start: 1, end: 3)) == Data("gTA".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["tiny.bref", "tiny.fa"])
    }
}

extension NativeReferenceSaveTests {
    @Test func fileMenuOpensANativeFASTAChooserAndTheSavePanelEnforcesBref() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let source = files.directory.appendingPathComponent("sample.fna")
        try Data(">one\nA".utf8).write(to: source)
        let controller = ViewerWindowController(session: ViewerSession())
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let menu = controller.makeFileMenu()
        menu.update()
        let create = try #require(menu.item(withTitle: "Create Reference…"))
        #expect(create.isEnabled)
        menu.performActionForItem(at: menu.index(of: create))
        let chooser = try #require(window.attachedSheet as? NSOpenPanel)
        #expect(!chooser.canChooseDirectories && !chooser.allowsMultipleSelection)
        menu.update()
        #expect(!create.isEnabled)
        chooser.cancel(nil)
        while window.attachedSheet === chooser { await Task.yield() }

        controller.chooseReferenceDestination(for: source)
        let save = try #require(window.attachedSheet as? NSSavePanel)
        #expect(!(save is NSOpenPanel))
        #expect(save.nameFieldStringValue == "sample.bref")
        #expect(save.allowedContentTypes.map(\.preferredFilenameExtension) == ["bref"])
        #expect(!save.allowsOtherFileTypes)
        save.cancel(nil)
        while window.attachedSheet === save { await Task.yield() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["sample.fna"])
    }
}

extension NativeReferenceSaveTests {
    @Test func cancelDuringImportKeepsTheConfirmedDestinationAndPausesBrowsing() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("large.fa")
        try Data(">one\n".utf8).write(to: input)
        let writer = try FileHandle(forWritingTo: input)
        try writer.seekToEnd()
        let block = Data(repeating: 65, count: 1 << 20)
        for _ in 0..<32 { try writer.write(contentsOf: block) }
        try writer.close()
        let output = files.directory.appendingPathComponent("existing.bref")
        let originalBytes = Data("previous contents".utf8)
        try originalBytes.write(to: output)
        let session = try await files.openedSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        session.editInterval("tiny:100-110")
        await session.submitInterval()?.value
        let before = session.presentation
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(controller.saveReference(from: input, to: destination))
        let sheet = try #require(window.attachedSheet)
        let controls = try #require(sheet.contentView).subviews
        let indicator = try #require(controls.compactMap { $0 as? NSProgressIndicator }.first)
        let progress = try #require(indicator.observedProgress)
        let cancel = try #require(controls.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" })
        let (updates, continuation) = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = progress.observe(\.completedUnitCount, options: [.initial, .new]) { value, _ in
            continuation.yield(value.completedUnitCount)
        }
        defer { observation.invalidate() }
        Task { await saving.value; continuation.finish() }
        for await count in updates where count > 0 { break }
        try #require(progress.completedUnitCount > 0 && progress.completedUnitCount < progress.totalUnitCount)
        controller.zoomIn(nil)
        #expect(session.presentation.target == before.target)
        #expect(try Data(contentsOf: output) == originalBytes)
        #expect(cancel.sendAction(cancel.action, to: cancel.target))
        await saving.value
        #expect(window.attachedSheet == nil)
        #expect(session.presentation.bamURL == before.bamURL)
        #expect(session.presentation.target == before.target)
        #expect(try Data(contentsOf: output) == originalBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["existing.bref", "large.fa"])
    }

    @Test func parseFailureShowsItsDiagnosticAndPreservesDestinationBytes() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("invalid.fa")
        let output = files.directory.appendingPathComponent("existing.bref")
        try Data(">one\nA!?".utf8).write(to: input)
        let originalBytes = Data("previous destination".utf8)
        try originalBytes.write(to: output)
        let controller = ViewerWindowController(session: ViewerSession())
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(controller.saveReference(from: input, to: destination))
        await saving.value
        let error = try #require(window.attachedSheet)
        defer { window.endSheet(error) }
        let root = try #require(error.contentView)
        func labels(in view: NSView) -> [String] {
            view.subviews.compactMap { ($0 as? NSTextField)?.stringValue } + view.subviews.flatMap { labels(in: $0) }
        }
        let text = labels(in: root)
        #expect(text.contains("Could not create existing.bref"))
        #expect(text.contains { $0.contains("‘!’ in one at base 2") })
        #expect(try Data(contentsOf: output) == originalBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["existing.bref", "invalid.fa"])
    }
}
