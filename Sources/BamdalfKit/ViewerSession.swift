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
    public var target: GenomicInterval?
    public var intervalError: String?
    public var isAlignmentSuppressed = false
    public var isLoading = false
    public var alignments: [Alignment] = []
    public var rowCount = 0
    public var verticalOffset = 0.0
    public var regionalError: RegionalLoadError?
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
    private var scrollGeneration: UInt64 = 0
    private var lastSuccessful: ViewerPresentation?
    private var editorGeneration: UInt64 = 0
    private var draftGeneration: UInt64?
    private var regionalRequestID = UUID()
    private var regionalTask: Task<Void, Never>?
    private let alignmentVisibilityLimit: Int64
    private let loadRegion: @Sendable (BAMFile, GenomicInterval) async throws -> [Alignment]
    private let loadFile: @Sendable (URL, URL) async throws -> BAMFile

    public init(loadBAM: @escaping @Sendable (URL, URL) async throws -> BAMFile = {
        try await BAMFile.open($0, indexURL: $1)
    }, loadRegion: @escaping @Sendable (BAMFile, GenomicInterval) async throws -> [Alignment] = {
        try await $0.alignments(in: $1)
    }, alignmentVisibilityLimit: Int64 = 10_000) {
        precondition(alignmentVisibilityLimit > 0)
        self.alignmentVisibilityLimit = alignmentVisibilityLimit
        loadFile = loadBAM
        self.loadRegion = loadRegion
    }

    public func editInterval(_ text: String) {
        guard text != presentation.intervalText else { return }
        editorGeneration += 1
        draftGeneration = editorGeneration
        presentation.intervalText = text
        presentation.intervalError = nil
    }

    public func resetIntervalEditor() {
        draftGeneration = nil
        presentation.intervalText = presentation.target?.formatted ?? ""
        presentation.intervalError = nil
    }

    @discardableResult
    public func submitInterval() -> Task<Void, Never>? {
        guard let bam else { return nil }
        do {
            let target = try GenomicInterval.parse(presentation.intervalText, references: presentation.references)
            draftGeneration = nil
            presentation.intervalText = target.formatted
            presentation.intervalError = nil
            if target == presentation.target { return regionalTask }
            let requestID = UUID()
            regionalRequestID = requestID
            presentation.regionalError = nil
            let generation = editorGeneration
            let initialScrollGeneration = scrollGeneration
            presentation.verticalOffset = 0
            let suppressed = target.end - target.start + 1 > alignmentVisibilityLimit
            var next = presentation
            next.target = target
            next.message = suppressed ? "Zoom in to see alignments" : ""
            next.isLoading = !suppressed
            next.isAlignmentSuppressed = suppressed
            next.alignments = []
            next.regionalError = nil
            if suppressed { next.rowCount = 0 }
            presentation = next
            if suppressed {
                regionalTask = nil
                lastSuccessful = presentation
                return nil
            }
            regionalTask = Task {
                do {
                    let alignments = try await loadRegion(bam, target)
                    guard regionalRequestID == requestID else { return }
                    presentation.alignments = Self.pack(alignments)
                    let requiredRows = (presentation.alignments.map(\.row).max() ?? -1) + 1
                    presentation.rowCount = scrollGeneration == initialScrollGeneration
                        ? requiredRows : max(presentation.rowCount, requiredRows)
                    presentation.isLoading = false
                    lastSuccessful = presentation
                } catch let error as RegionalLoadError {
                    guard regionalRequestID == requestID else { return }
                    restoreSuccessfulView(for: error, generation: generation)
                } catch {
                    guard regionalRequestID == requestID else { return }
                    restoreSuccessfulView(for: RegionalLoadError(interval: target, message: error.localizedDescription), generation: generation)
                }
                presentation.isLoading = false
                regionalTask = nil
            }
            return regionalTask
        } catch let error as IntervalValidationError {
            presentation.intervalError = error.message
        } catch {
            presentation.intervalError = "Enter a valid reference:start-end interval."
        }
        return nil
    }

    public func scrollVertically(to offset: Double) {
        guard offset.isFinite else { return }
        let offset = max(0, offset)
        guard offset != presentation.verticalOffset else { return }
        scrollGeneration += 1
        presentation.verticalOffset = offset
    }

    private static func pack(_ records: [Alignment]) -> [Alignment] {
        var result = records.sorted {
            $0.drawnStart == $1.drawnStart ? $0.id < $1.id : $0.drawnStart < $1.drawnStart
        }
        var ends: [Int64] = []
        for index in result.indices {
            let start = result[index].drawnStart
            if let row = ends.firstIndex(where: { $0 < start }) {
                result[index].row = row
                ends[row] = result[index].drawnEnd
            } else {
                result[index].row = ends.count
                ends.append(result[index].drawnEnd)
            }
        }
        return result
    }

    private func restoreSuccessfulView(for error: RegionalLoadError, generation: UInt64) {
        var restored = presentation
        restored.target = lastSuccessful?.target
        restored.alignments = lastSuccessful?.alignments ?? []
        restored.rowCount = lastSuccessful?.rowCount ?? 0
        restored.verticalOffset = 0
        restored.message = lastSuccessful?.message ?? "Enter a genomic interval"
        restored.isLoading = false
        restored.isAlignmentSuppressed = lastSuccessful?.isAlignmentSuppressed ?? false
        if draftGeneration == nil || draftGeneration! <= generation {
            restored.intervalText = restored.target?.formatted ?? ""
            restored.intervalError = nil
            draftGeneration = nil
        }
        restored.regionalError = RegionalLoadError(id: regionalRequestID, interval: error.interval, message: error.message)
        presentation = restored
    }

    public func dismissRegionalError(_ id: UUID) {
        guard presentation.regionalError?.id == id else { return }
        presentation.regionalError = nil
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
            regionalRequestID = UUID()
            regionalTask = nil
            lastSuccessful = nil
            draftGeneration = nil
            presentation = ViewerPresentation()
            presentation.bamURL = file.url
            presentation.indexURL = file.indexURL
            presentation.references = file.references
            presentation.windowTitle = "\(url.lastPathComponent) — Bamdalf"
            presentation.message = "Enter a genomic interval"
            presentation.intervalText = ""
            presentation.target = nil
            presentation.intervalError = nil
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
