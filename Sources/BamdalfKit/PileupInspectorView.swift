import AppKit

@MainActor
final class PileupInspectorView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private let outside = NSTextField(labelWithString: "outside current view")
    private let detail = NSTextField(wrappingLabelWithString: "")
    let closeButton = NSButton(title: "Close", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.lineBreakMode = .byTruncatingTail
        outside.textColor = .secondaryLabelColor
        outside.setContentCompressionResistancePriority(.required, for: .horizontal)
        let header = NSStackView(views: [heading, outside])
        header.spacing = 8
        for view in [header, detail, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            header.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
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

    func show(_ inspection: PileupInspection?, columnVisible: Bool) {
        outside.isHidden = inspection == nil || columnVisible
        isHidden = inspection == nil
        heading.stringValue = inspection?.heading ?? ""
        detail.stringValue = inspection?.detail ?? ""
    }
}
