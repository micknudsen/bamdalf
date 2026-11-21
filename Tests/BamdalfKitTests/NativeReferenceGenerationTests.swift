import AppKit
import BamdalfKit
import Testing

extension NativeReferenceSaveTests {
    @Test(arguments: ["direct", "hard-link", "symbolic-link", "renamed"])
    func referenceOpenedDuringGenerationCannotBeReplaced(alias: String) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("input.fa")
        let output = files.directory.appendingPathComponent("reference.bref")
        let selected = files.directory.appendingPathComponent("selected.bref")
        try Data(">tiny\nACGTACGT".utf8).write(to: input)
        try ReferenceBundle.create(from: input, at: output, name: "Original", creator: "test")
        let original = try Data(contentsOf: output)
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let session = ViewerSession(prefetch: .disabled)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        defer { controller.window?.close(); controller.referenceCreation.window?.close() }
        controller.createReference(nil)
        let gate = ImportGate()
        defer { gate.release() }
        let saving = try #require(controller.referenceCreation.saveReference(from: input, name: "Replacement", to: destination, progress: gate.progress))
        await gate.wait()
        switch alias {
        case "hard-link": try FileManager.default.linkItem(at: output, to: selected)
        case "symbolic-link": try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: output)
        case "renamed":
            try FileManager.default.moveItem(at: output, to: selected)
            try FileManager.default.linkItem(at: selected, to: output)
        default: break
        }
        await session.openReference(alias == "direct" ? output : selected)
        session.editInterval("tiny:2-5")
        await session.submitInterval()?.value
        session.editInterval("later draft")
        gate.release()
        await saving.value
        #expect(try Data(contentsOf: output) == original)
        #expect(session.presentation.referenceName == "Original")
        #expect(session.presentation.target == GenomicInterval(reference: "tiny", start: 2, end: 5))
        #expect(session.presentation.intervalText == "later draft")
        let form = try #require(controller.referenceCreation.window)
        #expect((try textField("Creation error", in: form)).stringValue.contains("open reference"))
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: files.directory.path)).contains { $0.hasPrefix(".bamdalf-") })
    }
    @Test func closingViewerKeepsGenerationAliveAndCreationCloseWaitsForCleanup() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("input.fa")
        let output = files.directory.appendingPathComponent("output.bref")
        try Data(">tiny\nACGT".utf8).write(to: input)
        let owner = ReferenceCreationController()
        let viewer = ViewerWindowController(session: ViewerSession(), referenceCreation: owner)
        viewer.showWindow(nil)
        viewer.createReference(nil)
        let form = try #require(owner.window)
        let gate = ImportGate()
        defer { gate.release(); owner.window?.close() }
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(owner.saveReference(from: input, name: "Result", to: destination, progress: gate.progress))
        await gate.wait()
        viewer.window?.performClose(nil)
        #expect(form.isVisible)
        form.performClose(nil)
        let keep = try #require(form.attachedSheet)
        #expect(keep.contentView?.subviews.isEmpty == false)
        form.endSheet(keep, returnCode: .alertFirstButtonReturn)
        while form.attachedSheet != nil { await Task.yield() }
        #expect(form.isVisible)
        form.performClose(nil)
        let cancel = try #require(form.attachedSheet)
        form.endSheet(cancel, returnCode: .alertSecondButtonReturn)
        while form.attachedSheet != nil { await Task.yield() }
        form.performClose(nil)
        #expect(form.isVisible)
        #expect(owner.saveReference(from: input, name: "duplicate", to: destination) == nil)
        gate.release()
        await saving.value
        #expect(owner.window == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["input.fa"])
    }

    @Test(arguments: [false, true])
    func quittingWaitsForCleanupAndKeepCreatingAbandonsQuit(alreadyCanceling: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("input.fa")
        let output = files.directory.appendingPathComponent("output.bref")
        try Data(">tiny\nACGT".utf8).write(to: input)
        let owner = ReferenceCreationController()
        owner.showWindow(nil)
        let form = try #require(owner.window)
        defer { owner.window?.close() }
        let gate = ImportGate()
        defer { gate.release() }
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(owner.saveReference(from: input, name: "Result", to: destination, progress: gate.progress))
        await gate.wait()
        var replies: [Bool] = []
        #expect(owner.requestTermination { replies.append($0) } == .terminateLater)
        let keep = try #require(form.attachedSheet)
        form.endSheet(keep, returnCode: .alertFirstButtonReturn)
        while form.attachedSheet != nil { await Task.yield() }
        #expect(replies == [false])
        #expect(form.isVisible)
        if alreadyCanceling { click(try button("Cancel", in: form)) }
        #expect(owner.requestTermination { replies.append($0) } == .terminateLater)
        let cancel = try #require(form.attachedSheet)
        #expect(owner.requestTermination { _ in Issue.record("Duplicate termination reply") } == .terminateLater)
        #expect(form.attachedSheet === cancel)
        form.endSheet(cancel, returnCode: .alertSecondButtonReturn)
        while form.attachedSheet != nil { await Task.yield() }
        #expect(owner.requestTermination { _ in Issue.record("Premature termination") } == .terminateLater)
        #expect(replies == [false])
        #expect(owner.saveReference(from: input, name: "duplicate", to: destination) == nil)
        gate.release()
        await saving.value
        #expect(replies == [false, true])
        #expect(owner.window == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["input.fa"])
    }

    @Test(arguments: [false, true])
    func cancellationSettlesBeforeOrAfterAtomicPublication(afterCommit: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("input.fa")
        let output = files.directory.appendingPathComponent("output.bref")
        try Data(">tiny\nAcGT".utf8).write(to: input)
        let original = Data("confirmed original bytes".utf8)
        try original.write(to: output)
        let owner = ReferenceCreationController()
        owner.showWindow(nil)
        let form = try #require(owner.window)
        defer { owner.window?.close() }
        let (events, signal) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let task = owner.saveReference(from: input, name: "Published", to: destination,
            publicationCheckpoint: { stage in
                if (stage == .published) == afterCommit {
                    signal.yield()
                    release.wait()
                }
            })
        let saving = try #require(task)
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        click(try button("Cancel", in: form))
        click(try button("Cancel", in: form))
        #expect(owner.saveReference(from: input, name: "duplicate", to: destination) == nil)
        release.signal()
        await saving.value
        if afterCommit {
            #expect(owner.window == nil)
            let bundle = try ReferenceBundle(opening: output)
            #expect(bundle.name == "Published")
            #expect(try await bundle.read(GenomicInterval(reference: "tiny", start: 1, end: 4)) == Data("AcGT".utf8))
            owner.showWindow(nil)
            let reopened = try #require(owner.window)
            #expect(reopened !== form)
            #expect((try textField("Creation error", in: reopened)).stringValue.isEmpty)
        } else {
            #expect(owner.window === form && form.isVisible)
            #expect((try textField("Creation error", in: form)).stringValue.isEmpty)
            #expect(try Data(contentsOf: output) == original)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["input.fa", "output.bref"])
    }

    @Test(arguments: [false, true], ["success", "cancel", "changed-destination"])
    func browsingAndSourceChangesSurviveGeneration(withBAM: Bool, outcome: String) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let input = files.directory.appendingPathComponent("input.fa")
        let first = files.directory.appendingPathComponent("first.bref")
        let later = files.directory.appendingPathComponent("later.bref")
        let output = files.directory.appendingPathComponent("output.bref")
        try Data((">tiny\n" + String(repeating: "A", count: 20_000)).utf8).write(to: input)
        try ReferenceBundle.create(from: input, at: first, name: "First", creator: "test")
        try ReferenceBundle.create(from: input, at: later, name: "Later", creator: "test")
        let session = ViewerSession(prefetch: .disabled)
        await session.openReference(first)
        if withBAM { try await files.openedSession(fixture: "rows", session: session) }
        session.editInterval("tiny:101-200")
        await session.submitInterval()?.value
        let viewer = ViewerWindowController(session: session) { _, _, complete in complete(later) }
        viewer.showWindow(nil)
        defer { viewer.window?.close(); viewer.referenceCreation.window?.close() }
        viewer.createReference(nil)
        let form = try #require(viewer.referenceCreation.window)
        let gate = ImportGate()
        defer { gate.release() }
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(viewer.referenceCreation.saveReference(from: input, name: "Created", to: destination, progress: gate.progress))
        await gate.wait()
        #expect(viewer.window?.attachedSheet == nil)
        let initial = session.presentation.target
        viewer.panRight(nil)
        #expect(session.presentation.target != initial)
        // Actual File action replaces the reference while the importer is stopped.
        let (opened, signal) = AsyncStream<Void>.makeStream()
        let render = session.onPresentationChange
        session.onPresentationChange = {
            render?()
            if session.presentation.referenceURL == later && !session.presentation.isOpening { signal.yield() }
        }
        viewer.openReference(nil)
        var iterator = opened.makeAsyncIterator()
        _ = await iterator.next()
        session.onPresentationChange = render
        if withBAM {
            try await files.openedSession(fixture: "comparison", session: session)
        }
        session.editInterval("tiny:151-175")
        await session.submitInterval()?.value
        session.editInterval("later unfinished draft")
        let chosen = session.presentation
        if outcome == "cancel" { click(try button("Cancel", in: form)) }
        if outcome == "changed-destination" { try Data("new destination".utf8).write(to: output) }
        gate.release()
        await saving.value
        #expect(session.presentation.referenceURL == later)
        #expect(session.presentation.referenceName == "Later")
        #expect(session.presentation.bamURL == chosen.bamURL)
        #expect(session.presentation.target == chosen.target)
        #expect(session.presentation.intervalText == "later unfinished draft")
        #expect(session.presentation.alignments == chosen.alignments)
        if outcome == "success" {
            #expect(viewer.referenceCreation.window == nil)
            #expect(try ReferenceBundle(opening: output).name == "Created")
        } else if outcome == "cancel" {
            #expect(form.isVisible)
            #expect(!FileManager.default.fileExists(atPath: output.path))
            #expect((try textField("Creation error", in: form)).stringValue.isEmpty)
        } else {
            #expect(form.isVisible)
            #expect(try Data(contentsOf: output) == Data("new destination".utf8))
            #expect((try textField("Creation error", in: form)).stringValue.contains("changed after confirmation"))
        }
    }

}

/// Stops a real import after input bytes have been consumed, without timing assumptions.
final class ImportGate: @unchecked Sendable {
    let progress = Progress(totalUnitCount: -1)
    private let semaphore = DispatchSemaphore(value: 0)
    private let events: AsyncStream<Void>
    private var observation: NSKeyValueObservation?

    init() {
        let (events, signal) = AsyncStream<Void>.makeStream()
        self.events = events
        observation = progress.observe(\.completedUnitCount, options: .new) { [semaphore] value, _ in
            if value.completedUnitCount > 0 {
                signal.yield()
                semaphore.wait()
            }
        }
    }

    func wait() async {
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
    }
    func release() { semaphore.signal() }
}
