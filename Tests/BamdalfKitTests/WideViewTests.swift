import Foundation
import AppKit
import Testing
import BamdalfKit

struct WideViewTests {
    @Test(arguments: [false, true])
    @MainActor
    func wideTargetsNeverQueryOrDrawAndBecomeSuccessfulRestorationViews(failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let requests = RegionRequests()
        let session = ViewerSession(loadRegion: { file, target in
            await requests.record(target.formatted)
            if target.start == 101 {
                await gate.pause(101)
                if failLate { throw RegionalLoadError(interval: target, message: "Stale failure") }
            }
            if target.start == 2001 { throw RegionalLoadError(interval: target, message: "Current failure") }
            return try await file.alignments(in: target)
        }, alignmentVisibilityLimit: 1000)
        let bam = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        session.editInterval("tiny:101-110")
        let old = session.submitInterval()
        await gate.waitFor(101)
        session.editInterval("tiny:1-10000")
        await session.submitInterval()?.value
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.message == "Zoom in to see alignments")
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.alignments.isEmpty)
        #expect(await requests.values == ["tiny:101-110"])
        await gate.release(101)
        await old?.value
        #expect(session.presentation.target?.formatted == "tiny:1-10,000")
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.alignments.isEmpty)
        session.editInterval("tiny:2001-2010")
        await session.submitInterval()?.value
        #expect(session.presentation.target?.formatted == "tiny:1-10,000")
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.message == "Zoom in to see alignments")
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:2,001-2,010")
        session.editInterval("tiny:1001-1014")
        await session.submitInterval()?.value
        #expect(!session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.alignments.map(\.name) == ["complex"])
        #expect(session.presentation.verticalOffset == 0)
    }
    @Test
    @MainActor
    func measuredProductionBoundaryKeepsTenKilobasesVisibleAndSuppressesAnythingWider() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let requests = RegionRequests()
        let session = ViewerSession(loadRegion: { file, target in
            await requests.record(target.formatted)
            return try await file.alignments(in: target)
        })
        let bam = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let scroll = try #require(window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        session.editInterval("tiny:1-10000")
        await session.submitInterval()?.value
        #expect(!session.presentation.alignments.isEmpty)
        #expect(!scroll.isHidden)
        session.editInterval("tiny:1-10001")
        await session.submitInterval()?.value
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.alignments.isEmpty)
        #expect(!scroll.isHidden, "The empty wide-view surface still receives pointer navigation")
        #expect(await requests.values == ["tiny:1-10,000"])
        #expect(window.contentView?.subviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "Zoom in to see alignments" && !$0.isHidden
        } == true)
    }

}

private actor RegionRequests {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
