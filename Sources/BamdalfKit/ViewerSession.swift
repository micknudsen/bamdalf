/// Presentation shared by the application session and its native workspace.
public struct ViewerPresentation {
    public let windowTitle: String
    public let message: String
}

@MainActor
public final class ViewerSession {
    public let presentation: ViewerPresentation

    public init() {
        presentation = ViewerPresentation(
            windowTitle: "Bamdalf",
            message: "No BAM file open"
        )
    }
}
