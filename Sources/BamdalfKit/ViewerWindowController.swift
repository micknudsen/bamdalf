import AppKit
import UniformTypeIdentifiers

@MainActor
public final class ViewerWindowController: NSWindowController, NSTextFieldDelegate, NSMenuItemValidation, NSWindowDelegate {
    public let referenceCreation: ReferenceCreationController
    let session: ViewerSession
    private let message = WorkspaceMessage(labelWithString: "")
    private let referenceField = NSTextField()
    private let intervalField = NSTextField()
    private let panLeftButton = NSButton()
    private let panRightButton = NSButton()
    private let zoomOutButton = NSButton()
    private let zoomInButton = NSButton()
    private let intervalError = NSTextField(wrappingLabelWithString: "")
    private let referenceRow = GenomicReferenceView(frame: .zero)
    private let referenceRowHeight: NSLayoutConstraint
    private let ruler = GenomicRulerView(frame: .zero)
    private let loadingIndicator = NSProgressIndicator()
    private let samplingWarning = SamplingWarningButton()
    private var regionalAlert: (id: UUID, alert: NSAlert)?
    private let alignmentScroll = NSScrollView()
    private let alignmentStack = GenomicAlignmentView(frame: .zero)
    private var isRendering = false
    private var isScrolling = false
    private var displayedSessionID: UUID?
    private var indexAlert: NSAlert?

    public typealias PresentReferencePanel = @MainActor (NSSavePanel, NSWindow, @escaping @MainActor (URL?) -> Void) -> Void
    let presentReferencePanel: PresentReferencePanel

    public init(session: ViewerSession, referenceCreation: ReferenceCreationController? = nil, presentReferencePanel: @escaping PresentReferencePanel = { panel, window, complete in
        panel.beginSheetModal(for: window) { response in
            let url = response == .OK ? panel.url : nil
            panel.orderOut(nil)
            complete(url)
        }
    }) {
        self.referenceCreation = referenceCreation ?? ReferenceCreationController(presentPanel: presentReferencePanel)
        self.presentReferencePanel = presentReferencePanel
        self.session = session
        referenceRowHeight = referenceRow.heightAnchor.constraint(equalToConstant: 0)
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
        intervalField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        intervalField.placeholderString = "reference:start-end"
        intervalField.setAccessibilityLabel("Genomic interval")
        intervalField.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(intervalField)
        referenceField.cell = ReferenceNameCell(textCell: "")
        referenceField.isEditable = false
        referenceField.isSelectable = false
        referenceField.isBezeled = true
        referenceField.bezelStyle = .roundedBezel
        referenceField.lineBreakMode = .byTruncatingTail
        referenceField.usesSingleLineMode = true
        referenceField.setAccessibilityLabel("Selected reference")
        referenceField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        referenceField.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(referenceField)
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!)
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false
        referenceField.addSubview(icon)
        let preferredIntervalWidth = intervalField.widthAnchor.constraint(equalToConstant: 360)
        preferredIntervalWidth.priority = NSLayoutConstraint.Priority(490)
        let preferredReferenceWidth = referenceField.widthAnchor.constraint(equalToConstant: 220)
        preferredReferenceWidth.priority = NSLayoutConstraint.Priority(480)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: referenceField.leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: referenceField.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            referenceField.leadingAnchor.constraint(equalTo: intervalField.trailingAnchor, constant: 38),
            referenceField.trailingAnchor.constraint(lessThanOrEqualTo: workspace.trailingAnchor, constant: -16),
            referenceField.centerYAnchor.constraint(equalTo: intervalField.centerYAnchor),
            referenceField.heightAnchor.constraint(equalTo: intervalField.heightAnchor),
            referenceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
            referenceField.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            preferredReferenceWidth, preferredIntervalWidth,
        ])
        for (button, symbol, label, action) in [
            (panLeftButton, "arrow.left", "Pan left", #selector(panLeft(_:))),
            (panRightButton, "arrow.right", "Pan right", #selector(panRight(_:))),
            (zoomOutButton, "minus", "Zoom out", #selector(zoomOut(_:))),
            (zoomInButton, "plus", "Zoom in", #selector(zoomIn(_:))),
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
            panRightButton.leadingAnchor.constraint(equalTo: panLeftButton.trailingAnchor, constant: 16),
            zoomOutButton.leadingAnchor.constraint(equalTo: panRightButton.trailingAnchor, constant: 16),
            zoomInButton.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor, constant: 16),
            intervalField.leadingAnchor.constraint(equalTo: zoomInButton.trailingAnchor, constant: 10),
            intervalField.topAnchor.constraint(equalTo: workspace.topAnchor, constant: 12),
            intervalField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
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
        samplingWarning.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(samplingWarning)
        NSLayoutConstraint.activate([
            samplingWarning.leadingAnchor.constraint(equalTo: intervalField.trailingAnchor, constant: 10),
            samplingWarning.centerYAnchor.constraint(equalTo: intervalField.centerYAnchor),
            samplingWarning.widthAnchor.constraint(equalToConstant: 18),
            samplingWarning.heightAnchor.constraint(equalToConstant: 18),
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
            ruler.topAnchor.constraint(equalTo: intervalError.bottomAnchor, constant: 12),
            ruler.heightAnchor.constraint(equalToConstant: 68),
        ])
        referenceRow.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(referenceRow)
        NSLayoutConstraint.activate([
            referenceRow.leadingAnchor.constraint(equalTo: ruler.leadingAnchor),
            referenceRow.trailingAnchor.constraint(equalTo: ruler.trailingAnchor),
            referenceRow.topAnchor.constraint(equalTo: ruler.bottomAnchor),
            referenceRowHeight,
        ])
        alignmentScroll.hasHorizontalScroller = false
        alignmentScroll.autohidesScrollers = true
        alignmentScroll.scrollerStyle = .overlay
        alignmentScroll.documentView = alignmentStack
        alignmentScroll.contentView.postsBoundsChangedNotifications = true
        alignmentScroll.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(alignmentScroll)
        NSLayoutConstraint.activate([
            alignmentScroll.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: 16),
            alignmentScroll.trailingAnchor.constraint(equalTo: workspace.trailingAnchor, constant: -16),
            ruler.leadingAnchor.constraint(equalTo: alignmentScroll.contentView.leadingAnchor),
            ruler.trailingAnchor.constraint(equalTo: alignmentScroll.contentView.trailingAnchor),
            alignmentScroll.topAnchor.constraint(equalTo: referenceRow.bottomAnchor, constant: 4),
            alignmentScroll.bottomAnchor.constraint(equalTo: workspace.bottomAnchor),
        ])
        workspace.addSubview(alignmentScroll, positioned: .below, relativeTo: message)
        window.contentView = workspace
        super.init(window: window)
        panLeftButton.target = self
        panRightButton.target = self
        zoomOutButton.target = self
        zoomInButton.target = self
        alignmentStack.canNavigate = { [weak self] in
            guard let self else { return false }
            return self.session.presentation.target != nil && !self.session.presentation.isOpening
                && self.window?.attachedSheet == nil
        }
        alignmentStack.beginDrag = { [weak session] in session?.beginAlignmentDrag() }
        alignmentStack.previewDrag = { [weak session] in session?.previewAlignmentDrag(horizontalFraction: $0) }
        alignmentStack.endDrag = { [weak session] in session?.endAlignmentDrag() }
        alignmentStack.zoomAt = { [weak session] direction, fraction in
            session?.zoom(direction, atHorizontalFraction: fraction)
        }
        window.delegate = self
        intervalField.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(alignmentDidScroll(_:)),
                                               name: NSView.boundsDidChangeNotification, object: alignmentScroll.contentView)
        alignmentScroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportDidResize(_:)),
                                               name: NSView.frameDidChangeNotification, object: alignmentScroll.contentView)
        session.onPresentationChange = { [weak self] in self?.render() }
        render()
        session.setViewportWidth(ruler.bounds.width)
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

    var canManageFiles: Bool { !session.presentation.isOpening && window?.attachedSheet == nil }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Popup choices also reach this validator while their sheet is open.
        switch menuItem.action {
        case #selector(openBAM(_:)), #selector(openReference(_:)):
            return canManageFiles
        case #selector(closeReference(_:)):
            return canManageFiles && session.selectedReference != nil
        case #selector(createReference(_:)):
            return true
        case #selector(goToInterval(_:)):
            return session.presentation.intervalEntryAvailable && window?.attachedSheet == nil
        default:
            return true
        }
    }

    public func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Open BAM…", action: #selector(openBAM(_:)), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Create Reference…", action: #selector(createReference(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Reference…", action: #selector(openReference(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Close Reference", action: #selector(closeReference(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
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

    @objc public func zoomOut(_ sender: Any?) {
        guard !session.presentation.isOpening, window?.attachedSheet == nil else { return }
        session.zoom(.out)
    }

    @objc public func zoomIn(_ sender: Any?) {
        guard !session.presentation.isOpening, window?.attachedSheet == nil else { return }
        session.zoom(.in)
    }

    @objc public func openReference(_ sender: Any?) {
        guard let window, canManageFiles else { return }
        let panel = NSOpenPanel()
        panel.title = "Open Reference"
        panel.prompt = "Open"
        panel.allowedContentTypes = [UTType(filenameExtension: "bref", conformingTo: .data)!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        presentReferencePanel(panel, window) { [weak self] url in
            guard let self, let url else { return }
            Task {
                await self.session.openReference(url)
                self.presentOpenResult()
            }
        }
    }

    @objc public func closeReference(_ sender: Any?) {
        guard canManageFiles else { return }
        session.closeReference()
    }

    @objc public func openBAM(_ sender: Any?) {
        guard let window, canManageFiles else { return }
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
        if isScrolling {
            alignmentStack.updateScrollOffset(presentation.verticalOffset)
            return
        }
        let referenceLength = presentation.target.flatMap { presentation.references.contig(named: $0.reference)?.length }
        let canNavigate = !presentation.isOpening && window?.attachedSheet == nil
        panLeftButton.isEnabled = canNavigate && (presentation.target?.start ?? 1) > 1
        panRightButton.isEnabled = canNavigate && (presentation.target?.end ?? 0) < (referenceLength ?? 0)
        let width = presentation.target.map { $0.end - $0.start + 1 } ?? 0
        zoomInButton.isEnabled = canNavigate && width > 1
        zoomOutButton.isEnabled = canNavigate && width > 0 && width < (referenceLength ?? 0)
        let name = presentation.referenceName ?? "No reference"
        if !referenceField.stringValue.utf8.elementsEqual(name.utf8) { referenceField.stringValue = name }
        referenceField.toolTip = presentation.referenceURL?.lastPathComponent
        window?.title = presentation.windowTitle
        message.stringValue = presentation.message
        intervalField.isHidden = !presentation.intervalEntryAvailable
        intervalField.isEnabled = presentation.intervalEntryAvailable
        if !intervalField.stringValue.utf8.elementsEqual(presentation.intervalText.utf8) {
            intervalField.stringValue = presentation.intervalText
        }
        intervalError.stringValue = presentation.intervalError ?? ""
        intervalError.isHidden = presentation.intervalError == nil
        samplingWarning.show(!presentation.isLoading && presentation.isDownsampled)
        loadingIndicator.isHidden = !presentation.isLoading
        if presentation.isLoading { loadingIndicator.startAnimation(nil) }
        else { loadingIndicator.stopAnimation(nil) }
        let loadingLabel = switch (presentation.bamURL, presentation.referenceURL) {
        case (.some, .some): "Loading genomic interval"
        case (nil, .some): "Loading reference"
        default: "Loading alignments"
        }
        loadingIndicator.setAccessibilityLabel(loadingLabel)
        referenceRowHeight.constant = presentation.referenceURL == nil ? 0 : 18
        referenceRow.isHidden = presentation.referenceURL == nil || presentation.target == nil
        referenceRow.presentation = presentation
        ruler.presentation = presentation
        ruler.isHidden = presentation.target == nil
        alignmentScroll.isHidden = presentation.target == nil
        alignmentScroll.hasVerticalScroller = presentation.bamURL != nil
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

    public func windowDidResize(_ notification: Notification) {
        render()
        session.setViewportWidth(ruler.bounds.width)
    }

    public func windowDidEndSheet(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.render() }
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

    @objc private func viewportDidResize(_ notification: Notification) {
        // AppKit can tile its scroller during a session render. Apply the settled
        // viewport width after that presentation change has finished.
        Task { @MainActor [weak self] in
            guard let self else { return }
            session.setViewportWidth(alignmentScroll.contentView.bounds.width)
        }
    }

    @objc private func alignmentDidScroll(_ notification: Notification) {
        guard !isRendering else { return }
        isScrolling = true
        defer { isScrolling = false }
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

/// Status text is visual; pointer navigation belongs to the alignment area beneath it.
private final class WorkspaceMessage: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ReferenceNameCell: NSTextFieldCell {
    override func drawInterior(withFrame frame: NSRect, in view: NSView) {
        // Reserve the leading space for the file icon inside the native bezel.
        super.drawInterior(withFrame: frame.divided(atDistance: 22, from: .minXEdge).remainder, in: view)
    }
}
