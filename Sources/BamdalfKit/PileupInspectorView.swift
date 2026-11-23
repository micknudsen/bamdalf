import AppKit

@MainActor
final class PileupInspectorView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    let closeButton = NSButton(title: "Close", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.lineBreakMode = .byTruncatingTail
        for view in [heading, detail, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            heading.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 2),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func show(_ inspection: PileupInspection?) {
        isHidden = inspection == nil
        heading.stringValue = inspection?.heading ?? ""
        detail.stringValue = inspection?.detail ?? ""
    }
}
