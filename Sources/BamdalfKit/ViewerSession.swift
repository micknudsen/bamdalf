import Foundation

public struct FileOpenError: Error, Equatable, Sendable {
    public let fileURL: URL
    public let message: String
}

public struct IndexChoice: Equatable, Sendable {
    public let bamURL: URL
    public let candidates: [URL]
}

/// Presentation shared by the application session and its native workspace.
public struct ViewerPresentation {
    public var windowTitle = "Bamdalf"
    public var message = "No BAM file open"
    public var bamURL: URL?
    public var indexURL: URL?
    public var references: [ReferenceSequence] = []
    public var intervalText = ""
    public var isOpening = false
    public var sessionID: UUID?
    public var intervalEntryAvailable: Bool { bamURL != nil }
    public var openError: FileOpenError?
    public var indexChoice: IndexChoice?
}

@MainActor
public final class ViewerSession {
    public private(set) var presentation = ViewerPresentation() {
        didSet { onPresentationChange?() }
    }
    public var onPresentationChange: (@MainActor () -> Void)?
    private var bam: BAMFile?
    private var openingID = UUID()
    private let loadFile: @Sendable (URL, URL) async throws -> BAMFile

    public init(loadBAM: @escaping @Sendable (URL, URL) async throws -> BAMFile = {
        try await BAMFile.open($0, indexURL: $1)
    }) {
        loadFile = loadBAM
    }

    public func editInterval(_ text: String) {
        presentation.intervalText = text
    }

    public func dismissOpenError() {
        presentation.openError = nil
    }

    public func openBAM(_ url: URL?) async {
        guard let url else { return }
        openingID = UUID()
        presentation.openError = nil
        presentation.indexChoice = nil
        presentation.isOpening = false
        let stem = url.deletingPathExtension()
        let candidates = [url.appendingPathExtension("bai"), stem.appendingPathExtension("bai"),
                          url.appendingPathExtension("csi"), stem.appendingPathExtension("csi")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if candidates.count > 1 {
            presentation.indexChoice = IndexChoice(bamURL: url, candidates: candidates)
            return
        }
        if let index = candidates.first {
            await loadBAM(url, index: index)
            return
        }
        presentation.openError = FileOpenError(
            fileURL: url,
            message: "No supported BAM index was found beside \(url.lastPathComponent). Expected a sibling BAI or CSI index."
        )
    }

    public func chooseIndex(_ url: URL?) async {
        let choice = presentation.indexChoice
        presentation.indexChoice = nil
        guard let url, let choice, choice.candidates.contains(url) else { return }
        await loadBAM(choice.bamURL, index: url)
    }

    private func loadBAM(_ url: URL, index: URL) async {
        let requestID = openingID
        presentation.isOpening = true
        defer {
            if requestID == openingID { presentation.isOpening = false }
        }
        do {
            let file = try await loadFile(url, index)
            guard requestID == openingID else { return }
            bam = file
            presentation.bamURL = file.url
            presentation.indexURL = file.indexURL
            presentation.references = file.references
            presentation.windowTitle = "\(url.lastPathComponent) — Bamdalf"
            presentation.message = "Enter a genomic interval"
            presentation.intervalText = ""
            presentation.sessionID = UUID()
        } catch let error as FileOpenError {
            guard requestID == openingID else { return }
            presentation.openError = error
        } catch {
            guard requestID == openingID else { return }
            presentation.openError = FileOpenError(fileURL: url, message: error.localizedDescription)
        }
    }
}
