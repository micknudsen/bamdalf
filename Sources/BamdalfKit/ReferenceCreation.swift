import AppKit
import UniformTypeIdentifiers

extension ViewerWindowController {
    @objc public func createReference(_ sender: Any?) {
        guard canManageFiles || referenceCreation.window != nil else { return }
        referenceCreation.present(for: window, canStart: { [weak self] in self?.canManageFiles == true }, selectedReference: { [weak self] in self?.session.selectedReference })
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
