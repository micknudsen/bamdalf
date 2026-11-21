import Foundation

/// Narrow synchronization points around the production atomic publication boundary.
public enum ReferencePublicationStage: Sendable {
    case readyToPublish
    case published
}

/// The session's selection commits and an import's final rename share this short
/// critical section. Parsing, validation and NSFileCoordinator waiting stay outside it.
final class ReferenceAccess: @unchecked Sendable {
    fileprivate let lock = NSLock()
    fileprivate var selected: ReferenceFileIdentity?

    func select(_ bundle: ReferenceBundle?, commit: () -> Void) throws {
        try lock.withLock {
            if let bundle, try ReferenceFileIdentity.at(bundle.url) != bundle.fileIdentity {
                throw ReferenceBundleError("The reference file changed while opening. Choose it again.")
            }
            selected = bundle?.fileIdentity
            commit()
        }
    }
}

/// Cancellation and publication settle once under the same lock as selection.
final class ReferencePublication: @unchecked Sendable {
    private let access: ReferenceAccess
    private var canceled = false
    private var committed = false

    init(access: ReferenceAccess) { self.access = access }

    func cancel() -> Bool {
        access.lock.withLock {
            guard !committed else { return false }
            canceled = true
            return true
        }
    }

    func publish(at url: URL, commit: () throws -> Void) throws {
        try access.lock.withLock {
            guard !canceled else { throw CancellationError() }
            if let selected = access.selected, try ReferenceFileIdentity.at(url) == selected {
                throw ReferenceBundleError("This is the open reference. Choose a different destination or close the reference first.")
            }
            try commit()
            committed = true
        }
    }
}
