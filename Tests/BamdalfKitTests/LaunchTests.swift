import Testing
import AppKit
import BamdalfKit

struct LaunchTests {
    @Test
    @MainActor
    func testNewSessionPresentsAnUnopenedWorkspace() {
        let session = ViewerSession()

        #expect(session.presentation.windowTitle == "Bamdalf")
        #expect(session.presentation.message == "No BAM file open")
    }

    @Test
    @MainActor
    func testNativeWindowShowsSessionInAFullWidthWorkspace() throws {
        _ = NSApplication.shared
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        workspace.layoutSubtreeIfNeeded()

        #expect(window.isVisible)
        #expect(window.title == "Bamdalf")
        #expect(window.toolbar == nil)
        #expect(!workspace.subviews.contains { $0 is NSSplitView })
        let message = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(message.stringValue == session.presentation.message)
        #expect(message.isEditable == false)
        #expect(abs(message.frame.midX - workspace.bounds.midX) < 1)

        window.setContentSize(NSSize(width: 1100, height: 720))
        workspace.layoutSubtreeIfNeeded()
        #expect(workspace.bounds.width == 1100)
        #expect(abs(message.frame.midX - 550) < 1)
    }
}
