import AppKit
import UniformTypeIdentifiers

/// Owns one transient creation form. Generation remains modal in this slice.
@MainActor
public final class ReferenceCreationController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let name = NSTextField()
    private let path = NSTextField()
    private let nameError = NSTextField(wrappingLabelWithString: "")
    private let pathError = NSTextField(wrappingLabelWithString: "")
    private let create = NSButton()
    private let browse = NSButton()
    private let indicator = NSProgressIndicator()
    private let cancel = NSButton()
    private let generationError = NSTextField(wrappingLabelWithString: "")
    private weak var viewerWindow: NSWindow?
    private var selectedReference: () -> ReferenceBundle? = { nil }
    private var canStart: () -> Bool = { true }
    private var operation: Task<Void, Never>?
    private var choosing = false
    private var editedName = false
    private let presentPanel: ViewerWindowController.PresentReferencePanel

    public init(presentPanel: @escaping ViewerWindowController.PresentReferencePanel = { panel, window, complete in
        panel.beginSheetModal(for: window) { response in
            let url = response == .OK ? panel.url : nil
            panel.orderOut(nil)
            complete(url)
        }
    }) {
        self.presentPanel = presentPanel
        super.init(window: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func present(for viewerWindow: NSWindow?, canStart: @escaping () -> Bool, selectedReference: @escaping () -> ReferenceBundle?) {
        if window == nil {
            self.viewerWindow = viewerWindow
            self.selectedReference = selectedReference
            self.canStart = canStart
        }
        showWindow(nil)
    }

    public override func showWindow(_ sender: Any?) {
        if window == nil {
            let form = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            form.title = "Create Reference"
            form.isReleasedWhenClosed = false
            form.delegate = self
            generationError.stringValue = ""
            nameError.stringValue = ""
            pathError.stringValue = ""
            name.stringValue = ""
            path.stringValue = ""
            editedName = false
            name.delegate = self
            path.delegate = self
            name.frame = NSRect(x: 24, y: 260, width: 510, height: 24)
            name.setAccessibilityLabel("Bundle name")
            path.frame = NSRect(x: 24, y: 180, width: 400, height: 24)
            path.setAccessibilityLabel("FASTA")
            form.contentView?.addSubview(name)
            form.contentView?.addSubview(path)
            browse.title = "Browse…"
            browse.target = self
            browse.action = #selector(browseFASTA(_:))
            browse.frame = NSRect(x: 430, y: 178, width: 104, height: 28)
            form.contentView?.addSubview(browse)
            for (label, y) in [("Bundle name", 290.0), ("FASTA", 210.0)] {
                let heading = NSTextField(labelWithString: label)
                heading.frame = NSRect(x: 24, y: y, width: 510, height: 20)
                form.contentView?.addSubview(heading)
            }
            for (error, label, y) in [(nameError, "Bundle name error", 234.0), (pathError, "FASTA error", 142.0)] {
                error.frame = NSRect(x: 24, y: y, width: 510, height: error === nameError ? 22 : 32)
                error.textColor = .systemRed
                error.font = .systemFont(ofSize: 11)
                error.setAccessibilityLabel(label)
                form.contentView?.addSubview(error)
            }
            create.title = "Create bundle"
            create.target = self
            create.action = #selector(createBundle(_:))
            create.keyEquivalent = "\r"
            create.frame = NSRect(x: 394, y: 20, width: 140, height: 32)
            form.contentView?.addSubview(create)
            generationError.frame = NSRect(x: 24, y: 66, width: 510, height: 70)
            generationError.textColor = .systemRed
            generationError.setAccessibilityLabel("Creation error")
            form.contentView?.addSubview(generationError)
            indicator.frame = NSRect(x: 24, y: 100, width: 510, height: 20)
            indicator.style = .bar
            indicator.setAccessibilityLabel("FASTA import progress")
            form.contentView?.addSubview(indicator)
            cancel.title = "Cancel"
            cancel.target = self
            cancel.action = #selector(cancelImport(_:))
            cancel.keyEquivalent = "\u{1b}"
            cancel.frame = create.frame
            form.contentView?.addSubview(cancel)
            updateControls()
            window = form
            form.center()
        }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard operation == nil else { return }
        if notification.object as? NSTextField === name { editedName = true }
        if notification.object as? NSTextField === path { suggestName() }
    }

    private func suggestName() {
        if !editedName {
            name.stringValue = (try? sourceURL().deletingPathExtension().lastPathComponent) ?? ""
        }
    }

    @objc private func browseFASTA(_ sender: Any?) {
        guard let window, !choosing, operation == nil, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose a local, uncompressed FASTA file."
        panel.prompt = "Choose FASTA"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        choosing = true
        presentPanel(panel, window) { [weak self] source in
            self?.choosing = false
            guard let self, let source else { return }
            self.path.stringValue = source.path
            self.suggestName()
        }
    }

    @objc private func createBundle(_ sender: Any?) {
        guard let window, !choosing, operation == nil, window.attachedSheet == nil else { return }
        window.makeFirstResponder(nil)
        nameError.stringValue = ""
        pathError.stringValue = ""
        var validatedName: String?
        var source: URL?
        do { validatedName = try ReferenceFormat.validatedName(name.stringValue) }
        catch { nameError.stringValue = error.localizedDescription }
        do { source = try validatedSource() }
        catch { pathError.stringValue = error.localizedDescription }
        guard let validatedName, let source else { return }
        name.stringValue = validatedName
        let panel = NSSavePanel()
        panel.title = "Create Reference"
        panel.nameFieldStringValue = suggestedFilename(validatedName)
        panel.allowedContentTypes = [UTType(filenameExtension: "bref", conformingTo: .data)!]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        let approval = ReferenceSaveApproval(protecting: selectedReference())
        panel.delegate = approval
        choosing = true
        presentPanel(panel, window) { [weak self] selected in
            guard let self else { return }
            guard selected != nil, let destination = approval.destination else {
                self.choosing = false
                return
            }
            // AppKit finishes removing the Save sheet before the form becomes
            // the viewer's generation sheet. Retain the guard across this turn.
            Task { @MainActor in
                self.choosing = false
                guard self.window === window else { return }
                self.saveReference(from: source, name: validatedName, to: destination)
            }
        }
    }

    /// Runs a confirmed Save with frozen inputs; the form stays unavailable until cleanup finishes.
    @discardableResult
    public func saveReference(from source: URL, name: String, to destination: ReferenceSaveDestination,
                              progress: Progress = Progress(totalUnitCount: -1)) -> Task<Void, Never>? {
        guard let window, !choosing, operation == nil, window.attachedSheet == nil else { return nil }
        generationError.stringValue = ""
        do {
            guard canStart() else {
                throw ReferenceBundleError("Wait for the viewer to finish opening a source, then try again.")
            }
            // Recheck the live selection without renewing the original Save approval.
            // The viewer sheet below prevents further source changes during import.
            _ = try ReferenceSaveDestination(confirmedURL: destination.url, protecting: selectedReference())
        } catch {
            generationError.stringValue = error.localizedDescription
            return nil
        }
        indicator.observedProgress = progress
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let creator = version.map { "bamdalf/\($0)" } ?? "bamdalf"
        let worker = Task.detached(priority: .userInitiated) {
            try ReferenceBundle.create(from: source, at: destination, name: name, creator: creator) { read, total in
                if read == 0 { progress.totalUnitCount = total }
                progress.completedUnitCount = read
            }
        }
        // Preserve the existing browsing pause until concurrent publication and
        // close/quit protection are delivered by the next implementation slice.
        window.orderOut(nil)
        viewerWindow?.beginSheet(window)
        operation = Task { @MainActor in
            let result = await worker.result
            window.sheetParent?.endSheet(window)
            window.orderOut(nil)
            self.operation = nil
            self.cancelCreation = nil
            self.indicator.observedProgress = nil
            self.updateControls()
            switch result {
            case .success:
                window.close()
            case .failure(let error):
                if !(error is CancellationError) {
                    self.generationError.stringValue = "Could not create \(destination.url.lastPathComponent): \(error.localizedDescription)"
                }
                window.makeKeyAndOrderFront(nil)
            }
        }
        cancelCreation = { worker.cancel() }
        updateControls()
        return operation
    }

    private var cancelCreation: (() -> Void)?

    @objc private func cancelImport(_ sender: Any?) {
        cancel.isEnabled = false
        cancelCreation?()
    }

    private func updateControls() {
        let running = operation != nil
        name.isEnabled = !running
        path.isEnabled = !running
        browse.isEnabled = !running
        create.isEnabled = !running
        create.isHidden = running
        indicator.isHidden = !running
        cancel.isHidden = !running
        cancel.isEnabled = running
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool { operation == nil && !choosing }

    private func sourceURL() throws -> URL {
        let entered = path.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: URL
        if entered.contains("://") {
            guard let url = URL(string: entered), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost" else {
                throw ReferenceBundleError("Choose a readable local FASTA file.")
            }
            source = url
        } else {
            guard !entered.isEmpty else { throw ReferenceBundleError("Choose a readable local FASTA file.") }
            source = URL(fileURLWithPath: (entered as NSString).expandingTildeInPath)
        }
        return source
    }

    private func validatedSource() throws -> URL {
        let source = try sourceURL()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        guard values.isRegularFile == true, values.isReadable == true,
              FileManager.default.isReadableFile(atPath: source.path) else {
            throw ReferenceBundleError("Choose a readable local FASTA file.")
        }
        return source
    }

    private func suggestedFilename(_ name: String) -> String {
        let unsafe = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let replaced = name.unicodeScalars.map { unsafe.contains($0) ? "_" : String($0) }.joined()
        let leaf = replaced.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Leave room for the extension under ordinary filesystem component limits.
        var result = ""
        for character in leaf {
            guard result.utf8.count + String(character).utf8.count <= 240 else { break }
            result.append(character)
        }
        return (result.isEmpty ? "Reference" : result) + ".bref"
    }

    public func windowWillClose(_ notification: Notification) { window = nil }
}
