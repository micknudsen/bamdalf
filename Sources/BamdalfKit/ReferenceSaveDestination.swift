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
        if let existing, try ReferenceFileIdentity.at(url) != existing {
            throw ReferenceBundleError("The destination changed after confirmation. Choose it again to save.")
        }
        let flags = existing == nil ? UInt32(RENAME_EXCL) : 0
        guard renamex_np(candidate.path, url.path, flags) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
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
