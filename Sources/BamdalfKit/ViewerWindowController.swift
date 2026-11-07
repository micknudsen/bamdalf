import AppKit

@MainActor
public final class ViewerWindowController: NSWindowController {
    private let session: ViewerSession

    public init(session: ViewerSession) {
        self.session = session
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = session.presentation.windowTitle
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        let workspace = NSView()
        let message = NSTextField(labelWithString: session.presentation.message)
        message.font = .systemFont(ofSize: 15)
        message.textColor = .secondaryLabelColor
        message.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: workspace.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: workspace.centerYAnchor),
        ])
        window.contentView = workspace
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(session:)")
    }
}
