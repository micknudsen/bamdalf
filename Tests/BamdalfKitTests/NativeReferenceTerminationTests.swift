import AppKit
import BamdalfKit
import Testing

@Suite(.serialized)
@MainActor
struct NativeReferenceTerminationTests {
    @Test(.timeLimit(.minutes(1)))
    func actualApplicationTerminationFollowsCompletedCleanup() async throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["BAMDALF_TESTING_TERMINATION"] != "1" {
            let host = try #require(Bundle.main.executableURL)
            let test = "actualApplicationTerminationFollowsCompletedCleanup"
            var arguments = ["--filter", test, "--testing-library", "swift-testing"]
            if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path") {
                arguments = ["--test-bundle-path", CommandLine.arguments[index + 1]] + arguments
            }
            let childArguments = arguments
            let (status, log) = try await Task.detached {
                let child = Process()
                child.executableURL = host
                child.arguments = childArguments
                child.environment = environment.merging(["BAMDALF_TESTING_TERMINATION": "1"]) { _, new in new }
                let output = Pipe()
                child.standardOutput = output
                child.standardError = output
                try child.run()
                let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                child.waitUntilExit()
                return (child.terminationStatus, log)
            }.value
            #expect(status == 0)
            #expect(log.contains("BAMDALF_TERMINATION_CLEANUP_COMPLETED"), "Termination host did not complete its native lifecycle check: \(log)")
            return
        }

        // Only this explicitly isolated host may send an actual application quit.
        let app = NSApplication.shared
        let files = try FixtureFiles()
        let input = files.directory.appendingPathComponent("input.fa")
        let output = files.directory.appendingPathComponent("output.bref")
        try Data(">tiny\nACGT".utf8).write(to: input)
        let owner = ReferenceCreationController()
        let delegate = TerminationDelegate(owner: owner, files: files)
        app.delegate = delegate
        owner.showWindow(nil)
        let form = try #require(owner.window)
        let gate = ImportGate()
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let saving = try #require(owner.saveReference(from: input, name: "Canceled", to: destination, progress: gate.progress))
        await gate.wait()
        // Native run-loop actions reproduce menu events without holding a Swift
        // MainActor task across AppKit's nested termination event loop.
        delegate.cancel = {
            if let sheet = form.attachedSheet {
                form.endSheet(sheet, returnCode: .alertSecondButtonReturn)
            }
            gate.release()
        }
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                let trigger = Timer(timeInterval: 0, repeats: false) { _ in
                    MainActor.assumeIsolated { app.terminate(nil) }
                }
                RunLoop.main.add(trigger, forMode: .common)
                app.run()
            }
        }
        await saving.value
        // Yield after worker completion so AppKit can finish unwinding its quit
        // event and deliver applicationWillTerminate before exiting the child.
        var termination = AsyncStream<Void> { _ in }.makeAsyncIterator()
        _ = await termination.next()
        Issue.record("Application did not terminate after cleanup")
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class TerminationDelegate: NSObject, NSApplicationDelegate {
    let owner: ReferenceCreationController
    let files: FixtureFiles
    var cancel: (() -> Void)?
    init(owner: ReferenceCreationController, files: FixtureFiles) {
        self.owner = owner
        self.files = files
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let result = owner.requestTermination { sender.reply(toApplicationShouldTerminate: $0) }
        let response = Timer(timeInterval: 0, repeats: false) { [self] _ in
            MainActor.assumeIsolated { cancel?() }
        }
        RunLoop.main.add(response, forMode: .common)
        RunLoop.main.add(response, forMode: .modalPanel)
        return result
    }
    func applicationWillTerminate(_ notification: Notification) {
        if owner.window == nil,
           (try? FileManager.default.contentsOfDirectory(atPath: files.directory.path)) == ["input.fa"] {
            FileHandle.standardOutput.write(Data("BAMDALF_TERMINATION_CLEANUP_COMPLETED\n".utf8))
        }
        files.remove()
    }
}
