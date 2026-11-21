import AppKit
import BamdalfKit
import Testing

@Suite(.serialized)
@MainActor
struct NativeReferenceSaveTests {
    @Test func creationFormKeepsInputsUntilItsWindowCloses() throws {
        _ = NSApplication.shared
        let controller = ViewerWindowController(session: ViewerSession())
        controller.showWindow(nil)
        defer { controller.window?.close() }
        controller.createReference(nil)
        let form = try #require(NSApplication.shared.windows.first { $0.title == "Create Reference" && $0.isVisible })
        defer { form.close() }
        let name = try #require(form.contentView?.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Bundle name" })
        let path = try #require(form.contentView?.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "FASTA" })
        #expect(name.stringValue.isEmpty && path.stringValue.isEmpty)
        name.stringValue = "draft"
        controller.createReference(nil)
        #expect(NSApplication.shared.windows.filter { $0.title == "Create Reference" && $0.isVisible }.count == 1)
        #expect(name.stringValue == "draft")
        form.close()
        controller.createReference(nil)
        let reopened = try #require(NSApplication.shared.windows.first { $0.title == "Create Reference" && $0.isVisible })
        defer { reopened.close() }
        #expect(reopened !== form)
        #expect(reopened.contentView?.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Bundle name" }?.stringValue == "")
    }

    @Test func fastaChangesSuggestNamesUntilTheUserEditsOne() throws {
        _ = NSApplication.shared
        var choice: URL? = URL(fileURLWithPath: "/tmp/browsed.fna")
        let controller = ViewerWindowController(session: ViewerSession()) { panel, owner, complete in
            #expect(panel is NSOpenPanel && owner.title == "Create Reference")
            complete(choice)
        }
        controller.createReference(nil)
        let form = try creationForm()
        defer { form.close() }
        let name = try textField("Bundle name", in: form)
        let path = try textField("FASTA", in: form)
        edit(path, to: "/tmp/first.release.fa")
        #expect(name.stringValue == "first.release")
        edit(path, to: URL(fileURLWithPath: "/tmp/local reference.fa").absoluteString)
        #expect(name.stringValue == "local reference")
        let browse = try button("Browse…", in: form)
        click(browse)
        #expect(path.stringValue == "/tmp/browsed.fna" && name.stringValue == "browsed")
        choice = nil
        click(browse)
        #expect(path.stringValue == "/tmp/browsed.fna")
        edit(name, to: "chosen")
        edit(path, to: "/tmp/second.fa")
        #expect(name.stringValue == "chosen")
        edit(name, to: "")
        edit(path, to: "/tmp/third.fa")
        #expect(name.stringValue.isEmpty)
    }

    @Test func invalidFieldsPreventSaveAndCanceledSaveRetainsValidatedInputs() throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let source = files.directory.appendingPathComponent("source.fa")
        try Data("invalid contents checked only during generation".utf8).write(to: source)
        var savedNames: [String] = []
        let controller = ViewerWindowController(session: ViewerSession()) { panel, owner, complete in
            #expect(!(panel is NSOpenPanel) && owner.title == "Create Reference")
            #expect(panel.allowedContentTypes.map(\.preferredFilenameExtension) == ["bref"])
            #expect(!panel.allowsOtherFileTypes)
            savedNames.append(panel.nameFieldStringValue)
            complete(nil)
        }
        controller.createReference(nil)
        let form = try creationForm()
        defer { form.close() }
        let name = try textField("Bundle name", in: form)
        let path = try textField("FASTA", in: form)
        let create = try button("Create bundle", in: form)
        click(create)
        #expect(!(try textField("Bundle name error", in: form)).stringValue.isEmpty)
        #expect(!(try textField("FASTA error", in: form)).stringValue.isEmpty)
        edit(name, to: String(repeating: "x", count: 4097))
        edit(path, to: source.path)
        click(create)
        #expect((try textField("Bundle name error", in: form)).stringValue.contains("4,096"))
        edit(name, to: "  ../My:reference/label  ")
        for invalid in ["/missing/file.fa", "https://example.org/input.fa", "file://remote/tmp/input.fa", files.directory.path] {
            edit(path, to: invalid)
            click(create)
            #expect(!(try textField("FASTA error", in: form)).stringValue.isEmpty)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: source.path)
        edit(path, to: source.path)
        click(create)
        #expect(!(try textField("FASTA error", in: form)).stringValue.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        #expect(savedNames.isEmpty)
        edit(path, to: source.path)
        click(create)
        #expect(savedNames.count == 1)
        let suggested = try #require(savedNames.first)
        #expect(!suggested.contains("/") && !suggested.contains(":") && !suggested.hasPrefix("."))
        #expect(suggested.hasSuffix(".bref"))
        #expect(name.stringValue == "../My:reference/label" && path.stringValue == source.path)
        #expect(create.isEnabled && form.isVisible)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["source.fa"])
    }

    @Test(.timeLimit(.minutes(1))) func confirmedSaveFreezesInputsAndCompletesQuietly() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("first.fa")
        let other = files.directory.appendingPathComponent("other.fa")
        let output = files.directory.appendingPathComponent("edited-output.bref")
        try Data(">first\nAcG".utf8).write(to: input)
        try Data(">other\nTTT".utf8).write(to: other)
        var pending: (@MainActor (URL?) -> Void)?
        let controller = ViewerWindowController(session: ViewerSession()) { panel, _, complete in
            do {
                #expect(panel.nameFieldStringValue == "Initial name.bref")
                try (panel.delegate as? ReferenceSaveApproval)?.panel(panel, validate: output)
                pending = complete
            } catch { Issue.record(error) }
        }
        controller.showWindow(nil)
        defer { controller.window?.close() }
        controller.createReference(nil)
        let form = try creationForm()
        edit(try textField("FASTA", in: form), to: input.path)
        edit(try textField("Bundle name", in: form), to: " Initial name ")
        click(try button("Create bundle", in: form))
        let confirm = try #require(pending)
        // Simulate later delivered edits and repeated actions while Save owns the form.
        edit(try textField("FASTA", in: form), to: other.path)
        edit(try textField("Bundle name", in: form), to: "Later name")
        click(try button("Create bundle", in: form))
        controller.createReference(nil)
        #expect(try creationForm() === form)
        let (closed, signal) = AsyncStream<Void>.makeStream()
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: form, queue: nil) { _ in signal.yield() }
        defer { NotificationCenter.default.removeObserver(observer) }
        confirm(output)
        var events = closed.makeAsyncIterator()
        try #require(await events.next() != nil)
        #expect(controller.referenceCreation.window == nil)
        #expect(controller.window?.attachedSheet == nil)
        let result = try ReferenceBundle(opening: output)
        #expect(result.name == "Initial name")
        #expect(try await result.read(GenomicInterval(reference: "first", start: 1, end: 3)) == Data("AcG".utf8))
        controller.createReference(nil)
        let reopened = try creationForm()
        defer { reopened.close() }
        #expect((try textField("Bundle name", in: reopened)).stringValue.isEmpty)
        edit(try textField("FASTA", in: reopened), to: other.path)
        #expect((try textField("Bundle name", in: reopened)).stringValue == "other")
    }

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
        controller.createReference(nil)
        let saving = try #require(controller.referenceCreation.saveReference(from: input, name: "Chosen name", to: approved))
        let progressSheet = try #require(window.attachedSheet)
        #expect(progressSheet.title == "Create Reference")
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
        let moved = files.directory.appendingPathComponent("moved-again.bref")
        let bases = "aCG" + String(repeating: "A", count: 19_997)
        try Data((">tiny\n" + bases).utf8).write(to: input)
        try Data("old destination".utf8).write(to: output)
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session) { panel, _, complete in
            if panel is NSOpenPanel {
                complete(panel.allowedContentTypes.first?.preferredFilenameExtension == "bref" ? moved : input)
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
        let form = try creationForm()
        click(try button("Browse…", in: form))
        edit(try textField("Bundle name", in: form), to: "  My named reference  ")
        click(try button("Create bundle", in: form))
        var end = completion.makeAsyncIterator()
        try #require(await end.next() != nil)
        #expect(session.presentation.referenceURL == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["reference.bref", "source.fa"])
        #expect(try ReferenceBundle(opening: output).name == "My named reference")
        try FileManager.default.moveItem(at: output, to: moved)
        try FileManager.default.removeItem(at: input)
        let (opened, signal) = AsyncStream<Void>.makeStream()
        let render = session.onPresentationChange
        session.onPresentationChange = {
            render?()
            if session.presentation.referenceURL == moved && !session.presentation.isOpening { signal.yield() }
        }
        let open = try #require(menu.item(withTitle: "Open Reference…"))
        menu.performActionForItem(at: menu.index(of: open))
        var opens = opened.makeAsyncIterator()
        _ = await opens.next()
        session.onPresentationChange = render

        #expect(session.presentation.referenceName == "My named reference")
        try await files.openedSession(fixture: "comparison", session: session)
        session.editInterval("tiny:1-77")
        await session.submitInterval()?.value
        let stored = try #require(session.presentation.referenceBases)
        #expect(stored.interval.start == 1 && stored.bases.starts(with: Data("aCG".utf8)))
        let workspace = try #require(window.contentView)
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Selected reference" })
        #expect(field.stringValue == "My named reference" && field.toolTip == "moved-again.bref")
        workspace.layoutSubtreeIfNeeded()
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        let forward = try #require(session.presentation.alignments.first { $0.name == "forward" })
        try #require(forward.row < 2)
        let bitmap = try renderAlignmentBitmap(in: stack, window: window)
        // comparison.sam places a C at 14 after its 2S3M1I1P prefix. The saved reference contains A.
        let x = Int(13.5 * stack.bounds.width / 77)
        let colors = (4...13).compactMap { bitmap.colorAt(x: x, y: forward.row * 18 + $0)?.usingColorSpace(.deviceRGB) }
        #expect(colors.contains { $0.blueComponent > $0.redComponent + 0.3 && $0.blueComponent > $0.greenComponent + 0.2 })
    }

    @Test func fileMenuOpensANativeFASTAChooserAndTheSavePanelEnforcesBref() async throws {
        // Dismissing a system file panel can stop the SwiftPM host's AppKit run
        // loop after this test returns. Give these real panels a dedicated host.
        let environment = ProcessInfo.processInfo.environment
        if environment["BAMDALF_TESTING_FILE_PANEL"] != "1",
           let host = Bundle.main.executableURL, host.lastPathComponent == "swiftpm-testing-helper",
           let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path") {
            let bundle = CommandLine.arguments[index + 1]
            let test = "fileMenuOpensANativeFASTAChooserAndTheSavePanelEnforcesBref"
            let (status, log) = try await Task.detached {
                let child = Process()
                child.executableURL = host
                child.arguments = ["--test-bundle-path", bundle, "--filter", test, "--testing-library", "swift-testing"]
                child.environment = environment.merging(["BAMDALF_TESTING_FILE_PANEL": "1"]) { _, new in new }
                let output = Pipe()
                child.standardOutput = output
                child.standardError = output
                try child.run()
                let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                child.waitUntilExit()
                return (child.terminationStatus, log)
            }.value
            #expect(status == 0)
            #expect(log.range(of: #"Test run with 1 test( in 1 suite)? passed after "#, options: .regularExpression) != nil,
                    "Native dialog host did not complete. Output: \(log)")
            return
        }
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
        let form = try creationForm()
        defer { form.close() }
        click(try button("Browse…", in: form))
        let chooser = try #require(form.attachedSheet as? NSOpenPanel)
        #expect(!chooser.canChooseDirectories && !chooser.allowsMultipleSelection)
        menu.update()
        #expect(create.isEnabled)
        chooser.cancel(nil)
        while form.attachedSheet === chooser { await Task.yield() }

        edit(try textField("FASTA", in: form), to: source.path)
        click(try button("Create bundle", in: form))
        let save = try #require(form.attachedSheet as? NSSavePanel)
        #expect(!(save is NSOpenPanel))
        #expect(save.nameFieldStringValue == "sample.bref")
        #expect(save.allowedContentTypes.map(\.preferredFilenameExtension) == ["bref"])
        #expect(!save.allowsOtherFileTypes)
        save.cancel(nil)
        while form.attachedSheet === save { await Task.yield() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["sample.fna"])
    }
}

extension NativeReferenceSaveTests {
    @Test(arguments: [false, true])
    func cancelDuringImportKeepsTheConfirmedDestinationAndPausesBrowsing(withBAM: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("small.fa")
        try Data(">one\nACGT".utf8).write(to: input)
        let output = files.directory.appendingPathComponent("existing.bref")
        let originalBytes = Data("previous contents".utf8)
        try originalBytes.write(to: output)
        let session = ViewerSession()
        if withBAM {
            try await files.openedSession(session: session)
            session.editInterval("tiny:100-110")
            await session.submitInterval()?.value
        }
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
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
        controller.createReference(nil)
        let form = try creationForm()
        edit(try textField("Bundle name", in: form), to: "retained")
        edit(try textField("FASTA", in: form), to: input.path)
        let saving = try #require(controller.referenceCreation.saveReference(from: input, name: "retained", to: destination, progress: progress))
        let sheet = try #require(window.attachedSheet)
        let controls = try #require(sheet.contentView).subviews
        let indicator = try #require(controls.compactMap { $0 as? NSProgressIndicator }.first)
        #expect(indicator.observedProgress === progress)
        let cancel = try #require(controls.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" })
        Task { await saving.value; continuation.finish() }
        var updatesIterator = updates.makeAsyncIterator()
        try #require(await updatesIterator.next() != nil)
        controller.createReference(nil)
        #expect(controller.referenceCreation.window === form)
        #expect((try textField("Bundle name", in: form)).isEnabled == false)
        #expect((try button("Create bundle", in: form)).isEnabled == false)
        #expect(controller.referenceCreation.saveReference(from: input, name: "duplicate", to: destination) == nil)
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
        #expect(form.isVisible)
        #expect((try textField("Bundle name", in: form)).stringValue == "retained")
        #expect((try textField("Creation error", in: form)).stringValue.isEmpty)
        #expect((try button("Create bundle", in: form)).isEnabled)
        observation.invalidate()
        let retry = try #require(controller.referenceCreation.saveReference(from: input, name: "retained", to: destination))
        await retry.value
        #expect(try ReferenceBundle(opening: output).name == "retained")
        #expect(controller.referenceCreation.window == nil)
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
        controller.createReference(nil)
        let form = try creationForm()
        edit(try textField("Bundle name", in: form), to: "invalid input")
        edit(try textField("FASTA", in: form), to: input.path)
        let saving = try #require(controller.referenceCreation.saveReference(from: input, name: "invalid input", to: destination))
        await saving.value
        #expect(window.attachedSheet == nil && form.isVisible)
        defer { form.close() }
        #expect((try textField("Bundle name", in: form)).stringValue == "invalid input")
        #expect((try button("Create bundle", in: form)).isEnabled)
        let root = try #require(form.contentView)
        func labels(in view: NSView) -> [String] {
            view.subviews.compactMap { ($0 as? NSTextField)?.stringValue } + view.subviews.flatMap { labels(in: $0) }
        }
        let text = labels(in: root)
        #expect(text.contains { $0.contains("Could not create existing.bref") })
        #expect(text.contains { $0.contains("‘!’ in one at base 2") })
        #expect(try Data(contentsOf: output) == originalBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["existing.bref", "invalid.fa"])
    }
}

@MainActor
func creationForm() throws -> NSWindow {
    try #require(NSApplication.shared.windows.first { $0.title == "Create Reference" && $0.isVisible })
}

@MainActor
func textField(_ label: String, in window: NSWindow) throws -> NSTextField {
    try #require(window.contentView?.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == label })
}

@MainActor
func button(_ title: String, in window: NSWindow) throws -> NSButton {
    try #require(window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.title == title })
}

@MainActor
func edit(_ field: NSTextField, to value: String) {
    field.stringValue = value
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
}

@MainActor
func click(_ button: NSButton) {
    #expect(button.sendAction(button.action, to: button.target))
}
