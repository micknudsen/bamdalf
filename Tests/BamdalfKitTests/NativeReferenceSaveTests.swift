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
    @Test(.timeLimit(.minutes(1))) func confirmedPanelResponsesSaveAndReopenTheBundleFromTheFileMenu() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("source.fa")
        let output = files.directory.appendingPathComponent("reference.bref")
        try Data(">one\naCG".utf8).write(to: input)
        try Data("old destination".utf8).write(to: output)
        let controller = ViewerWindowController(session: ViewerSession()) { panel, _, complete in
            if panel is NSOpenPanel {
                complete(input)
                return
            }
            do {
                let delegate = try #require(panel.delegate as? ReferenceSaveApproval)
                try delegate.panel(panel, validate: output)
                complete(output)
            } catch {
                Issue.record(error)
                complete(nil)
            }
        }
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification,
                                                               object: window, queue: nil) { _ in continuation.yield() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let menu = controller.makeFileMenu()
        let create = try #require(menu.item(withTitle: "Create Reference…"))
        menu.performActionForItem(at: menu.index(of: create))
        var end = completion.makeAsyncIterator()
        try #require(await end.next() != nil)
        let bundle = try ReferenceBundle(opening: output)
        #expect(try await bundle.read(GenomicInterval(reference: "one", start: 1, end: 3)) == Data("aCG".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["reference.bref", "source.fa"])
    }

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
        let input = files.directory.appendingPathComponent("small.fa")
        try Data(">one\nACGT".utf8).write(to: input)
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
        let progress = Progress(totalUnitCount: -1)
        let (updates, continuation) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let observation = progress.observe(\.completedUnitCount, options: .new) { value, _ in
            if value.completedUnitCount > 0 {
                continuation.yield()
                release.wait()
            }
        }
        defer {
            release.signal()
            observation.invalidate()
        }
        let saving = try #require(controller.saveReference(from: input, to: destination, progress: progress))
        let sheet = try #require(window.attachedSheet)
        let controls = try #require(sheet.contentView).subviews
        let indicator = try #require(controls.compactMap { $0 as? NSProgressIndicator }.first)
        #expect(indicator.observedProgress === progress)
        let cancel = try #require(controls.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" })
        Task { await saving.value; continuation.finish() }
        var updatesIterator = updates.makeAsyncIterator()
        try #require(await updatesIterator.next() != nil)
        controller.zoomIn(nil)
        #expect(session.presentation.target == before.target)
        #expect(try Data(contentsOf: output) == originalBytes)
        #expect(cancel.sendAction(cancel.action, to: cancel.target))
        release.signal()
        await saving.value
        #expect(window.attachedSheet == nil)
        #expect(session.presentation.bamURL == before.bamURL)
        #expect(session.presentation.target == before.target)
        #expect(try Data(contentsOf: output) == originalBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["existing.bref", "small.fa"])
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
