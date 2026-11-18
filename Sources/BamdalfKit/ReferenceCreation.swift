import AppKit
import UniformTypeIdentifiers

extension ViewerWindowController {
    @objc public func createReference(_ sender: Any?) {
        guard let window, canManageFiles else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose a local, uncompressed FASTA file."
        panel.prompt = "Choose FASTA"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        presentReferencePanel(panel, window) { [weak self] source in
            guard let source else { return }
            Task { @MainActor in
                guard let self else { return }
                self.chooseReferenceDestination(for: source, protecting: self.session.selectedReference)
            }
        }
    }

    public func chooseReferenceDestination(for source: URL, protecting selectedReference: ReferenceBundle? = nil) {
        guard let window, canManageFiles else { return }
        let panel = NSSavePanel()
        panel.title = "Create Reference"
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".bref"
        panel.allowedContentTypes = [UTType(filenameExtension: "bref", conformingTo: .data)!]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        let approval = ReferenceSaveApproval(protecting: selectedReference)
        panel.delegate = approval
        presentReferencePanel(panel, window) { [weak self] selected in
            guard selected != nil, let destination = approval.destination else { return }
            Task { @MainActor in self?.saveReference(from: source, to: destination) }
        }
    }

    /// Completes the native Save panel's confirmed selection, without changing viewer sources.
    @discardableResult
    public func saveReference(from source: URL, to destination: ReferenceSaveDestination,
                              progress: Progress = Progress(totalUnitCount: -1)) -> Task<Void, Never>? {
        guard let window, canManageFiles else { return nil }
        let sheet = ReferenceCreationPanel(destination: destination.url, progress: progress)
        window.beginSheet(sheet)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let creator = version.map { "bamdalf/\($0)" } ?? "bamdalf"
        let worker = Task.detached(priority: .userInitiated) {
            try ReferenceBundle.create(from: source, at: destination, creator: creator) { read, total in
                if read == 0 { progress.totalUnitCount = total }
                progress.completedUnitCount = read
            }
        }
        sheet.cancelCreation = { worker.cancel() }
        return Task { @MainActor in
            let result = await worker.result
            window.endSheet(sheet)
            if case .failure(let error) = result, !(error is CancellationError) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Could not create \(destination.url.lastPathComponent)"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }
}

/// AppKit validates the final URL as part of its standard Save/Replace flow.
@MainActor
public final class ReferenceSaveApproval: NSObject, NSOpenSavePanelDelegate {
    let selectedReference: ReferenceBundle?
    private(set) var destination: ReferenceSaveDestination?

    init(protecting selectedReference: ReferenceBundle?) { self.selectedReference = selectedReference }

    public func panel(_ sender: Any, validate url: URL) throws {
        destination = try ReferenceSaveDestination(confirmedURL: url, protecting: selectedReference)
    }
}

@MainActor
private final class ReferenceCreationPanel: NSPanel {
    var cancelCreation: (() -> Void)?

    init(destination: URL, progress: Progress) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                   styleMask: [.titled], backing: .buffered, defer: false)
        title = "Creating Reference"
        let label = NSTextField(labelWithString: destination.lastPathComponent)
        label.lineBreakMode = .byTruncatingMiddle
        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.observedProgress = progress
        indicator.setAccessibilityLabel("FASTA import progress")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelImport(_:)))
        cancel.keyEquivalent = "\u{1b}"
        guard let contentView else { return }
        for view in [label, indicator, cancel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            indicator.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            indicator.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            indicator.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            cancel.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            cancel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    @objc private func cancelImport(_ sender: NSButton) {
        sender.isEnabled = false
        cancelCreation?()
    }
}
