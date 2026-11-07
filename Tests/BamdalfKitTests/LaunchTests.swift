import Testing
import BamdalfKit

struct LaunchTests {
    @Test
    @MainActor
    func testNewSessionPresentsAnUnopenedWorkspace() {
        let session = ViewerSession()

        #expect(session.presentation.windowTitle == "Bamdalf")
        #expect(session.presentation.message == "No BAM file open")
    }
}
