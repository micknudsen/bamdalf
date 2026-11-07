import Foundation
import Testing
import BamdalfKit

struct OpenOrderingTests {
    @Test(arguments: [false, true])
    @MainActor
    func obsoleteOpenCompletionCannotReplaceTheNewerBAMOrShowAnError(failLate: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let late = directory.appendingPathComponent("late.bam")
        let newer = directory.appendingPathComponent("newer.bam")
        for bam in [late, newer] {
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam"), to: bam)
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam.bai"),
                                            to: bam.appendingPathExtension("bai"))
        }
        let gate = OpenGate()
        let session = ViewerSession(loadBAM: { url, index in
            let result = try await BAMFile.open(url, indexURL: index)
            if url == late {
                await gate.suspend()
                if failLate { throw CocoaError(.fileReadUnknown) }
            }
            return result
        })
        let earlier = Task { await session.openBAM(late) }
        await gate.waitUntilSuspended()
        await session.openBAM(newer)
        #expect(session.presentation.bamURL == newer)
        await gate.release()
        await earlier.value

        #expect(session.presentation.bamURL == newer)
        #expect(session.presentation.openError == nil)
        #expect(session.presentation.indexChoice == nil)
        #expect(!session.presentation.isOpening)
    }
}

private actor OpenGate {
    private var suspended: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspended = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilSuspended() async {
        if suspended != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() {
        suspended?.resume()
        suspended = nil
    }
}
