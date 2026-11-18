import Darwin
import Foundation

/// The destination approved by the native Save panel.
public struct ReferenceSaveDestination: Sendable {
    public let url: URL
    private let existing: ReferenceFileIdentity?

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

    func publish(_ candidate: URL) throws {
        try Task.checkCancellation()
        guard let existing else {
            guard renamex_np(candidate.path, url.path, UInt32(RENAME_EXCL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var publicationError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try Task.checkCancellation()
                guard try ReferenceFileIdentity.at(target) == existing,
                      try target == url || ReferenceFileIdentity.at(url) == existing else {
                    throw ReferenceBundleError("The destination changed after confirmation. Choose it again to save.")
                }
                guard rename(candidate.path, target.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } catch {
                publicationError = error
            }
        }
        if let error = coordinationError ?? publicationError { throw error }
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
