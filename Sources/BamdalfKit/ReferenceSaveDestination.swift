import Darwin
import Foundation

/// The destination approved by the native Save panel.
public struct ReferenceSaveDestination: Sendable {
    public let url: URL
    private let existing: ReferenceFileIdentity?
    private var publication: ReferencePublication?
    private var checkpoint: @Sendable (ReferencePublicationStage) -> Void = { _ in }

    init(freshURL: URL) throws {
        try ReferenceFormat.checkURL(freshURL)
        url = freshURL
        existing = nil
    }

    public init(confirmedURL: URL, protecting selected: ReferenceBundle? = nil) throws {
        try ReferenceFormat.checkURL(confirmedURL)
        url = confirmedURL
        existing = try ReferenceFileIdentity.at(url)
        if let selected, existing == selected.fileIdentity {
            throw ReferenceBundleError("This is the open reference. Choose a different destination or close the reference first.")
        }
    }

    func coordinated(with publication: ReferencePublication,
                     checkpoint: @escaping @Sendable (ReferencePublicationStage) -> Void) -> Self {
        var copy = self
        copy.publication = publication
        copy.checkpoint = checkpoint
        return copy
    }

    func publish(_ candidate: URL) throws {
        try Task.checkCancellation()
        checkpoint(.readyToPublish)
        // Coordination can wait on other processes; do not hold the selection lock here.
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var publicationError: Error?
        var committed = false
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                let commit = {
                    try Task.checkCancellation()
                    guard try ReferenceFileIdentity.at(target) == existing,
                          try target == url || ReferenceFileIdentity.at(url) == existing else {
                        throw ReferenceBundleError("The destination changed after confirmation. Choose it again to save.")
                    }
                    let result = existing == nil
                        ? renamex_np(candidate.path, target.path, UInt32(RENAME_EXCL))
                        : rename(candidate.path, target.path)
                    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                }
                if let publication { try publication.publish(at: target, commit: commit) }
                else { try commit() }
                committed = true
            } catch {
                publicationError = error
            }
        }
        if committed { checkpoint(.published) }
        else if let error = coordinationError ?? publicationError { throw error }
        else { throw ReferenceBundleError("The destination could not be coordinated for saving. Try again.") }
    }

}

struct ReferenceFileIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t

    static func at(_ url: URL) throws -> Self? {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return Self(device: info.st_dev, inode: info.st_ino)
    }
}
