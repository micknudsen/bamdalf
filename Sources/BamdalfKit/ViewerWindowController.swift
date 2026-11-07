import AppKit
import UniformTypeIdentifiers

@MainActor
public final class ViewerWindowController: NSWindowController, NSTextFieldDelegate, NSMenuItemValidation, NSWindowDelegate {
    private let session: ViewerSession
    private let message = NSTextField(labelWithString: "")
    private let intervalField = NSTextField()
    private let panLeftButton = NSButton()
    private let panRightButton = NSButton()
    private let intervalError = NSTextField(wrappingLabelWithString: "")
    private let ruler = GenomicRulerView(frame: .zero)
    private let loadingIndicator = NSProgressIndicator()
    private var regionalAlert: (id: UUID, alert: NSAlert)?
    private let alignmentScroll = NSScrollView()
    private let alignmentStack = GenomicAlignmentView(frame: .zero)
    private var isRendering = false
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
        for (button, symbol, label, action) in [
            (panLeftButton, "arrow.left", "Pan left", #selector(panLeft(_:))),
            (panRightButton, "arrow.right", "Pan right", #selector(panRight(_:))),
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.setAccessibilityLabel(label)
            button.toolTip = label
            button.bezelStyle = .rounded
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            workspace.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32),
                button.centerYAnchor.constraint(equalTo: intervalField.centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            panLeftButton.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: 16),
            panRightButton.leadingAnchor.constraint(equalTo: panLeftButton.trailingAnchor, constant: 4),
            intervalField.leadingAnchor.constraint(equalTo: panRightButton.trailingAnchor, constant: 10),
            intervalField.topAnchor.constraint(equalTo: workspace.topAnchor, constant: 12),
            intervalField.widthAnchor.constraint(equalToConstant: 360),
        ])
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.setAccessibilityLabel("Loading alignments")
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.leadingAnchor.constraint(equalTo: intervalField.trailingAnchor, constant: 10),
            loadingIndicator.centerYAnchor.constraint(equalTo: intervalField.centerYAnchor),
        ])
        intervalError.font = .systemFont(ofSize: 12)
        intervalError.textColor = .systemRed
        intervalError.setAccessibilityLabel("Interval validation")
        intervalError.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(intervalError)
        NSLayoutConstraint.activate([
            intervalError.leadingAnchor.constraint(equalTo: intervalField.leadingAnchor),
            intervalError.topAnchor.constraint(equalTo: intervalField.bottomAnchor, constant: 4),
            intervalError.trailingAnchor.constraint(lessThanOrEqualTo: workspace.trailingAnchor, constant: -16),
        ])
        ruler.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(ruler)
        NSLayoutConstraint.activate([
            ruler.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: 16),
            ruler.trailingAnchor.constraint(equalTo: workspace.trailingAnchor, constant: -16),
            ruler.topAnchor.constraint(equalTo: intervalError.bottomAnchor, constant: 12),
            ruler.heightAnchor.constraint(equalToConstant: 68),
        ])
        alignmentScroll.hasVerticalScroller = true
        alignmentScroll.hasHorizontalScroller = false
        alignmentScroll.autohidesScrollers = true
        alignmentScroll.scrollerStyle = .overlay
        alignmentScroll.documentView = alignmentStack
        alignmentScroll.contentView.postsBoundsChangedNotifications = true
        alignmentScroll.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(alignmentScroll)
        NSLayoutConstraint.activate([
            alignmentScroll.leadingAnchor.constraint(equalTo: ruler.leadingAnchor),
            alignmentScroll.trailingAnchor.constraint(equalTo: ruler.trailingAnchor),
            alignmentScroll.topAnchor.constraint(equalTo: ruler.bottomAnchor, constant: 4),
            alignmentScroll.bottomAnchor.constraint(equalTo: workspace.bottomAnchor),
        ])
        window.contentView = workspace
        super.init(window: window)
        panLeftButton.target = self
        panRightButton.target = self
        window.delegate = self
        intervalField.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(alignmentDidScroll(_:)),
                                               name: NSView.boundsDidChangeNotification, object: alignmentScroll.contentView)
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

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === intervalField, window?.attachedSheet == nil,
              session.presentation.intervalEntryAvailable else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            session.submitInterval()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            session.resetIntervalEditor()
            return true
        default:
            return false
        }
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Popup choices also reach this validator while their sheet is open.
        switch menuItem.action {
        case #selector(openBAM(_:)):
            return !session.presentation.isOpening && window?.attachedSheet == nil
        case #selector(goToInterval(_:)):
            return session.presentation.intervalEntryAvailable && window?.attachedSheet == nil
        default:
            return true
        }
    }

    public func makeGoMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        let item = menu.addItem(withTitle: "Go to Interval", action: #selector(goToInterval(_:)), keyEquivalent: "l")
        item.target = self
        return menu
    }

    @objc public func goToInterval(_ sender: Any?) {
        guard session.presentation.intervalEntryAvailable, window?.attachedSheet == nil else { return }
        window?.makeFirstResponder(intervalField)
        intervalField.selectText(sender)
    }

    @objc public func panLeft(_ sender: Any?) {
        guard !session.presentation.isOpening, window?.attachedSheet == nil else { return }
        session.pan(.left)
    }

    @objc public func panRight(_ sender: Any?) {
        guard !session.presentation.isOpening, window?.attachedSheet == nil else { return }
        session.pan(.right)
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
        guard !isRendering else { return }
        isRendering = true
        defer { isRendering = false }
        let presentation = session.presentation
        let referenceLength = presentation.references.first { $0.name == presentation.target?.reference }?.length
        let canNavigate = !presentation.isOpening && window?.attachedSheet == nil
        panLeftButton.isEnabled = canNavigate && (presentation.target?.start ?? 1) > 1
        panRightButton.isEnabled = canNavigate && (presentation.target?.end ?? 0) < (referenceLength ?? 0)
        window?.title = presentation.windowTitle
        message.stringValue = presentation.message
        intervalField.isHidden = !presentation.intervalEntryAvailable
        intervalField.isEnabled = presentation.intervalEntryAvailable
        if intervalField.stringValue != presentation.intervalText {
            intervalField.stringValue = presentation.intervalText
        }
        intervalError.stringValue = presentation.intervalError ?? ""
        intervalError.isHidden = presentation.intervalError == nil
        loadingIndicator.isHidden = !presentation.isLoading
        if presentation.isLoading { loadingIndicator.startAnimation(nil) }
        else { loadingIndicator.stopAnimation(nil) }
        ruler.presentation = presentation
        ruler.isHidden = presentation.target == nil
        alignmentScroll.isHidden = presentation.target == nil || presentation.isAlignmentSuppressed
        window?.contentView?.layoutSubtreeIfNeeded()
        let size = alignmentScroll.contentSize
        alignmentStack.frame = NSRect(x: 0, y: 0, width: size.width,
                                      height: max(CGFloat(presentation.rowCount) * GenomicAlignmentView.rowHeight,
                                                  size.height + CGFloat(presentation.verticalOffset)))
        alignmentStack.presentation = presentation
        alignmentScroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(presentation.verticalOffset)))
        alignmentScroll.reflectScrolledClipView(alignmentScroll.contentView)
        if presentation.sessionID != displayedSessionID {
            displayedSessionID = presentation.sessionID
            window?.makeFirstResponder(intervalField)
        }
        presentRegionalError()
    }

    public func windowDidResize(_ notification: Notification) { render() }

    public func windowDidEndSheet(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.presentRegionalError() }
    }

    private func presentRegionalError() {
        guard let window else { return }
        if let shown = regionalAlert, shown.id != session.presentation.regionalError?.id {
            regionalAlert = nil
            window.endSheet(shown.alert.window)
        }
        guard let error = session.presentation.regionalError, regionalAlert == nil,
              window.isVisible, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not load \(error.interval.formatted)"
        alert.informativeText = error.message
        alert.addButton(withTitle: "OK")
        regionalAlert = (error.id, alert)
        alert.beginSheetModal(for: window) { [weak self] _ in
            guard let self else { return }
            if self.regionalAlert?.id == error.id { self.regionalAlert = nil }
            self.session.dismissRegionalError(error.id)
        }
    }

    @objc private func alignmentDidScroll(_ notification: Notification) {
        guard !isRendering else { return }
        session.scrollVertically(to: Double(alignmentScroll.contentView.bounds.origin.y))
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
