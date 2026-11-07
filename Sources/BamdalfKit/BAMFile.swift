import Foundation
import CBAM

public struct ReferenceSequence: Equatable, Sendable {
    public let name: String
    public let length: Int64
}

/// Owns one opened BAM/header/index. Native access stays inside this actor.
public actor BAMFile {
    public nonisolated let url: URL
    public nonisolated let indexURL: URL
    public nonisolated let references: [ReferenceSequence]
    private let handle: BAMHandle

    public static func open(_ url: URL, indexURL: URL) async throws -> BAMFile {
        try await Task.detached { try BAMFile(url, indexURL: indexURL) }.value
    }

    private init(_ url: URL, indexURL: URL) throws {
        var message = [CChar](repeating: 0, count: 1024)
        var indexFailed: Int32 = 0
        guard let pointer = bamdalf_bam_open(url.path, indexURL.path, &message, message.count, &indexFailed) else {
            throw FileOpenError(fileURL: indexFailed == 0 ? url : indexURL,
                                message: String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        handle = BAMHandle(pointer)
        self.url = url
        self.indexURL = indexURL
        references = (0..<bamdalf_reference_count(pointer)).map { reference in
            ReferenceSequence(name: String(cString: bamdalf_reference_name(pointer, reference)),
                              length: bamdalf_reference_length(pointer, reference))
        }
    }
}

// Only BAMFile owns/uses this handle. The wrapper permits safe destruction when
// the actor's last reference is released on a different executor.
private final class BAMHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { bamdalf_bam_close(pointer) }
}
