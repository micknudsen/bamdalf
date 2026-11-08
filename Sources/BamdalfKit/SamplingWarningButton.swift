import AppKit

/// Native tooltip on hover, equivalent popover on keyboard focus.
@MainActor
final class SamplingWarningButton: NSButton {
    static let explanation = "Downsampled: some alignments are not shown."
    private let helpPopover = NSPopover()

    init() {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: Self.explanation)
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .systemOrange
        toolTip = Self.explanation
        setAccessibilityLabel(Self.explanation)
        setAccessibilityHelp(Self.explanation)
        target = self
        action = #selector(showExplanation)
        let label = NSTextField(wrappingLabelWithString: Self.explanation)
        label.frame = NSRect(x: 12, y: 10, width: 260, height: 36)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: 56))
        controller.view.addSubview(label)
        helpPopover.contentViewController = controller
        helpPopover.behavior = .transient
        helpPopover.animates = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { showExplanation() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        helpPopover.close()
        return super.resignFirstResponder()
    }

    func show(_ visible: Bool) {
        isHidden = !visible
        if !visible { helpPopover.close() }
    }

    @objc private func showExplanation() {
        guard !isHidden, window != nil else { return }
        helpPopover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }
}
