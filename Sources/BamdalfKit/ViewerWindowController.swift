import AppKit
import UniformTypeIdentifiers

@MainActor
public final class ViewerWindowController: NSWindowController, NSTextFieldDelegate, NSMenuItemValidation {
    private let session: ViewerSession
    private let message = NSTextField(labelWithString: "")
    private let intervalField = NSTextField()
    private var displayedSessionID: UUID?
    private var indexAlert: NSAlert?

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
        message.font = .systemFont(ofSize: 15)
        message.textColor = .secondaryLabelColor
        message.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: workspace.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: workspace.centerYAnchor),
        ])
        intervalField.placeholderString = "reference:start-end"
        intervalField.setAccessibilityLabel("Genomic interval")
        intervalField.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(intervalField)
        NSLayoutConstraint.activate([
            intervalField.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: 16),
            intervalField.topAnchor.constraint(equalTo: workspace.topAnchor, constant: 12),
            intervalField.widthAnchor.constraint(equalToConstant: 360),
        ])
        window.contentView = workspace
        super.init(window: window)
        intervalField.delegate = self
        session.onPresentationChange = { [weak self] in self?.render() }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(session:)")
    }

    public func controlTextDidChange(_ notification: Notification) {
        session.editInterval(intervalField.stringValue)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Popup choices also reach this validator while their sheet is open.
        guard menuItem.action == #selector(openBAM(_:)) else { return true }
        return !session.presentation.isOpening && window?.attachedSheet == nil
    }

    @objc public func openBAM(_ sender: Any?) {
        guard let window, !session.presentation.isOpening, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Open BAM"
        panel.prompt = "Open"
        panel.allowedContentTypes = [UTType(filenameExtension: "bam") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            Task { @MainActor in
                await self.openBAM(at: panel.url)
            }
        }
    }

    /// Completes the native file chooser's selection through the viewer session.
    public func openBAM(at url: URL?) async {
        await session.openBAM(url)
        presentOpenResult()
    }

    private func render() {
        let presentation = session.presentation
        window?.title = presentation.windowTitle
        message.stringValue = presentation.message
        intervalField.isHidden = !presentation.intervalEntryAvailable
        intervalField.isEnabled = presentation.intervalEntryAvailable
        if intervalField.stringValue != presentation.intervalText {
            intervalField.stringValue = presentation.intervalText
        }
        if presentation.sessionID != displayedSessionID {
            displayedSessionID = presentation.sessionID
            window?.makeFirstResponder(intervalField)
        }
    }

    private func presentOpenResult() {
        guard let window, window.isVisible else { return }
        if let choice = session.presentation.indexChoice {
            presentIndexChoice(choice, for: window)
        } else if let error = session.presentation.openError {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not open \(error.fileURL.lastPathComponent)"
            alert.informativeText = "\(error.fileURL.path)\n\n\(error.message)"
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window) { [weak self] _ in self?.session.dismissOpenError() }
        }
    }

    private func presentIndexChoice(_ choice: IndexChoice, for window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Choose a BAM index"
        alert.informativeText = "Multiple supported indexes were found beside \(choice.bamURL.lastPathComponent). Choose the index to open."
        let openButton = alert.addButton(withTitle: "Open")
        openButton.isEnabled = false
        alert.addButton(withTitle: "Cancel")
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        picker.setAccessibilityLabel("BAM index")
        picker.addItem(withTitle: "Choose an index…")
        picker.addItems(withTitles: choice.candidates.map(\.lastPathComponent))
        picker.target = self
        picker.action = #selector(indexSelectionChanged(_:))
        alert.accessoryView = picker
        indexAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let selected = picker.indexOfSelectedItem - 1
            let index = response == .alertFirstButtonReturn && choice.candidates.indices.contains(selected)
                ? choice.candidates[selected] : nil
            self.indexAlert = nil
            Task { @MainActor in
                await self.session.chooseIndex(index)
                self.presentOpenResult()
            }
        }
    }

    @objc private func indexSelectionChanged(_ sender: NSPopUpButton) {
        indexAlert?.buttons.first?.isEnabled = sender.indexOfSelectedItem > 0
    }
}
