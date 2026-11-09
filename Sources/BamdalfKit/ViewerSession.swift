import Foundation

public struct FileOpenError: Error, Equatable, Sendable {
    public let fileURL: URL
    public let message: String
}

public struct IndexChoice: Equatable, Sendable {
    public let bamURL: URL
    public let candidates: [URL]
}

public enum PanDirection: Sendable {
    case left, right
}

public enum ZoomDirection: Sendable {
    case `in`, out

    func resizedWidth(_ width: Int64, maximum: Int64) -> Int64 {
        switch self {
        case .in: width / 2 + width % 2
        case .out: width > maximum / 2 ? maximum : width * 2
        }
    }
}

/// Presentation shared by the application session and its native workspace.
public struct ViewerPresentation {
    public var windowTitle = "bamdalf"
    public var message = "No BAM file open"
    public var bamURL: URL?
    public var indexURL: URL?
    public var references: [ReferenceSequence] = []
    public var intervalText = ""
    public var target: GenomicInterval?
    public var previewOffsetInBases = 0.0
    public var intervalError: String?
    public var isAlignmentSuppressed = false
    public var isLoading = false
    public var isDownsampled = false
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
    private var lastSuccessfulCandidates: [Alignment] = []
    private var sampling: AlignmentSampling
    private let samplingSeed: @Sendable () -> UInt64
    private var editorGeneration: UInt64 = 0
    private var draftGeneration: UInt64?
    private var regionalRequestID = UUID()
    private var regionalTask: Task<Void, Never>?
    private var dragOrigin: ViewerPresentation?
    private var deferredRegionalCompletion: (@MainActor () -> Void)?
    private var regionalData = RegionalData()
    private let alignmentVisibilityLimit: Int64
    private let loadRegion: @Sendable (BAMFile, GenomicInterval) async throws -> [Alignment]
    private let loadFile: @Sendable (URL, URL) async throws -> BAMFile

    public init(loadBAM: @escaping @Sendable (URL, URL) async throws -> BAMFile = {
        try await BAMFile.open($0, indexURL: $1)
    }, loadRegion: @escaping @Sendable (BAMFile, GenomicInterval) async throws -> [Alignment] = {
        try await $0.alignments(in: $1)
    }, alignmentVisibilityLimit: Int64 = 10_000, samplingGroupBudget: Int = 2_000,
                samplingSeed: @escaping @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) },
                samplingPriority: (@Sendable (UInt64, [UInt8]) -> UInt64)? = nil) {
        precondition(alignmentVisibilityLimit > 0)
        self.alignmentVisibilityLimit = alignmentVisibilityLimit
        self.sampling = AlignmentSampling(budget: samplingGroupBudget, priority: samplingPriority)
        self.samplingSeed = samplingSeed
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

    public func beginAlignmentDrag() {
        guard presentation.target != nil, !presentation.isOpening, dragOrigin == nil else { return }
        dragOrigin = presentation
    }

    /// Pointer displacement as a fraction of the viewport width, from pointer-down.
    public func previewAlignmentDrag(horizontalFraction: Double) {
        guard horizontalFraction.isFinite, let origin = dragOrigin, let target = origin.target,
              let reference = presentation.references.first(where: { $0.name == target.reference }) else { return }
        let minimum = 1 - target.start
        let maximum = reference.length - target.end
        let exactShift = min(Double(maximum), max(Double(minimum), -horizontalFraction * Double(target.end - target.start + 1)))
        let displacement = exactShift.rounded(.toNearestOrAwayFromZero)
        let shift = displacement <= Double(minimum) ? minimum
            : displacement >= Double(maximum) ? maximum : Int64(displacement)
        let preview = GenomicInterval(reference: target.reference, start: target.start + shift, end: target.end + shift)
        let remainder = exactShift - Double(shift)
        let visibleBases = GenomicInterval(reference: preview.reference,
                                           start: remainder < 0 ? max(1, preview.start - 1) : preview.start,
                                           end: remainder > 0 ? min(reference.length, preview.end + 1) : preview.end)
        let available = regionalData.available(for: visibleBases)
        var next = presentation
        next.target = preview
        next.previewOffsetInBases = remainder
        let selected = sampling.select(origin.isAlignmentSuppressed ? [] : available.records)
        next.alignments = Self.pack(selected.records, retaining: presentation.alignments)
        next.isDownsampled = selected.isDownsampled
        next.rowCount = max(presentation.rowCount, (next.alignments.map(\.row).max() ?? -1) + 1)
        next.isLoading = false
        presentation = next
    }

    @discardableResult
    public func endAlignmentDrag() -> Task<Void, Never>? {
        let preview = presentation
        let target = presentation.target
        guard let restored = restoreDragOrigin() else { return nil }
        if let target, target != restored.origin.target {
            presentation.alignments = preview.alignments
            presentation.rowCount = preview.rowCount
            presentation.intervalText = target.formatted
            return submitInterval(preservingPanContinuity: true)
        }
        let task = regionalTask
        restored.completion?()
        return task
    }

    private func restoreDragOrigin() -> (origin: ViewerPresentation, completion: (@MainActor () -> Void)?)? {
        guard var origin = dragOrigin else { return nil }
        let completion = deferredRegionalCompletion
        dragOrigin = nil
        deferredRegionalCompletion = nil
        origin.intervalText = presentation.intervalText
        origin.intervalError = presentation.intervalError
        origin.verticalOffset = presentation.verticalOffset
        presentation = origin
        return (origin, completion)
    }

    /// Pan by half the inclusive width, rounding an odd half up to a whole base.
    @discardableResult
    public func pan(_ direction: PanDirection) -> Task<Void, Never>? {
        guard let target = presentation.target,
              let reference = presentation.references.first(where: { $0.name == target.reference }) else { return nil }
        let width = target.end - target.start + 1
        let step = width / 2 + width % 2
        let shift: Int64
        switch direction {
        case .left: shift = -min(step, target.start - 1)
        case .right: shift = min(step, reference.length - target.end)
        }
        guard shift != 0 else { return nil }
        presentation.intervalText = GenomicInterval(reference: target.reference,
                                                    start: target.start + shift, end: target.end + shift).formatted
        return submitInterval(preservingPanContinuity: true)
    }

    /// Halve (rounding up) or double width, breaking center ties toward lower coordinates.
    @discardableResult
    public func zoom(_ direction: ZoomDirection) -> Task<Void, Never>? {
        guard let target = presentation.target,
              let reference = presentation.references.first(where: { $0.name == target.reference }) else { return nil }
        let width = target.end - target.start + 1
        let newWidth = direction.resizedWidth(width, maximum: reference.length)
        guard newWidth != width else { return nil }
        let difference = width - newWidth
        let offset = difference / 2 - (difference < 0 && difference % 2 != 0 ? 1 : 0)
        let start = min(max(1, target.start + offset), reference.length - newWidth + 1)
        presentation.intervalText = GenomicInterval(reference: target.reference,
                                                    start: start, end: start + (newWidth - 1)).formatted
        return submitInterval()
    }

    /// Center on the base hit in the viewport; even-width center ties go left.
    @discardableResult
    public func zoom(_ direction: ZoomDirection, atHorizontalFraction fraction: Double) -> Task<Void, Never>? {
        guard fraction.isFinite, let target = presentation.target,
              let reference = presentation.references.first(where: { $0.name == target.reference }) else { return nil }
        let width = target.end - target.start + 1
        let newWidth = direction.resizedWidth(width, maximum: reference.length)
        guard newWidth != width else { return nil }
        let position = min(1, max(0, fraction)) * Double(width)
        let offset = position >= Double(width - 1) ? width - 1 : Int64(position)
        let locus = target.start + offset
        let start = min(max(1, locus - newWidth / 2), reference.length - newWidth + 1)
        presentation.intervalText = GenomicInterval(reference: target.reference,
                                                    start: start, end: start + (newWidth - 1)).formatted
        return submitInterval(preservingPanContinuity: true)
    }

    @discardableResult
    public func submitInterval() -> Task<Void, Never>? {
        submitInterval(preservingPanContinuity: false)
    }

    private func submitInterval(preservingPanContinuity: Bool) -> Task<Void, Never>? {
        guard let bam else { return nil }
        do {
            let target = try GenomicInterval.parse(presentation.intervalText, references: presentation.references)
            if let restored = restoreDragOrigin(), target == restored.origin.target {
                restored.completion?()
            }
            draftGeneration = nil
            presentation.intervalText = target.formatted
            presentation.intervalError = nil
            if target == presentation.target { return regionalTask }
            let requestID = UUID()
            regionalRequestID = requestID
            presentation.regionalError = nil
            let generation = editorGeneration
            let initialScrollGeneration = scrollGeneration
            let suppressed = target.end - target.start + 1 > alignmentVisibilityLimit
            let previous = presentation.target
            let continuous = !suppressed && !presentation.isAlignmentSuppressed && previous?.reference == target.reference
                && (preservingPanContinuity || (previous!.start <= target.end && previous!.end >= target.start))
            let available = regionalData.available(for: target)
            var next = presentation
            next.target = target
            next.message = suppressed ? "Zoom in to see alignments" : ""
            next.isLoading = !suppressed && !available.missing.isEmpty
            next.isAlignmentSuppressed = suppressed
            let selected = sampling.select(suppressed ? [] : available.records)
            next.alignments = Self.pack(selected.records, retaining: continuous ? presentation.alignments : [])
            next.isDownsampled = selected.isDownsampled
            if !continuous { next.verticalOffset = 0 }
            let availableRows = (next.alignments.map(\.row).max() ?? -1) + 1
            next.rowCount = continuous ? max(next.rowCount, availableRows) : availableRows
            next.regionalError = nil
            if suppressed { next.rowCount = 0 }
            presentation = next
            if suppressed {
                regionalTask = nil
                lastSuccessful = presentation
                lastSuccessfulCandidates = []
                return nil
            }
            if available.missing.isEmpty {
                regionalTask = nil
                lastSuccessfulCandidates = available.records
                lastSuccessful = presentation
                return nil
            }
            regionalTask = Task {
                do {
                    var records = available.records
                    for (index, missing) in available.missing.enumerated() {
                        let loaded = try await loadRegion(bam, missing)
                        guard regionalRequestID == requestID else { return }
                        regionalData.insert(loaded, for: missing, keeping: target)
                        records = RegionalData.eligible(records + loaded, for: target)
                        if dragOrigin == nil && index + 1 < available.missing.count {
                            let selected = sampling.select(records)
                            presentation.alignments = Self.pack(selected.records, retaining: presentation.alignments)
                            presentation.isDownsampled = selected.isDownsampled
                            let requiredRows = (presentation.alignments.map(\.row).max() ?? -1) + 1
                            presentation.rowCount = continuous || scrollGeneration != initialScrollGeneration
                                ? max(presentation.rowCount, requiredRows) : requiredRows
                        }
                    }
                    regionalData.insert(records, for: target, keeping: target)
                    completeRegionalLoad(.success(records), requestID: requestID, generation: generation,
                                         initialScrollGeneration: initialScrollGeneration, continuous: continuous)
                } catch let error as RegionalLoadError {
                    completeRegionalLoad(.failure(RegionalLoadError(interval: target, message: error.message)),
                                         requestID: requestID, generation: generation,
                                         initialScrollGeneration: initialScrollGeneration, continuous: continuous)
                } catch {
                    completeRegionalLoad(.failure(RegionalLoadError(interval: target, message: error.localizedDescription)),
                                         requestID: requestID, generation: generation,
                                         initialScrollGeneration: initialScrollGeneration, continuous: continuous)
                }
            }
            return regionalTask
        } catch let error as IntervalValidationError {
            presentation.intervalError = error.message
        } catch {
            presentation.intervalError = "Enter a valid reference:start-end interval."
        }
        return nil
    }

    private func completeRegionalLoad(_ result: Result<[Alignment], RegionalLoadError>, requestID: UUID,
                                      generation: UInt64, initialScrollGeneration: UInt64, continuous: Bool) {
        guard regionalRequestID == requestID else { return }
        if dragOrigin != nil {
            deferredRegionalCompletion = { [weak self] in
                self?.completeRegionalLoad(result, requestID: requestID, generation: generation,
                                           initialScrollGeneration: initialScrollGeneration, continuous: continuous)
            }
            return
        }
        switch result {
        case .success(let records):
            let selected = sampling.select(records)
            presentation.alignments = Self.pack(selected.records, retaining: presentation.alignments)
            presentation.isDownsampled = selected.isDownsampled
            lastSuccessfulCandidates = records
            let requiredRows = (presentation.alignments.map(\.row).max() ?? -1) + 1
            presentation.rowCount = continuous || scrollGeneration != initialScrollGeneration
                ? max(presentation.rowCount, requiredRows) : requiredRows
            presentation.isLoading = false
            lastSuccessful = presentation
        case .failure(let error):
            restoreSuccessfulView(for: error, generation: generation)
        }
        presentation.isLoading = false
        regionalTask = nil
    }

    public func scrollVertically(to offset: Double) {
        guard offset.isFinite else { return }
        let offset = max(0, offset)
        guard offset != presentation.verticalOffset else { return }
        scrollGeneration += 1
        presentation.verticalOffset = offset
    }

    private static func pack(_ records: [Alignment], retaining previous: [Alignment] = []) -> [Alignment] {
        var result = records.sorted {
            $0.drawnStart == $1.drawnStart ? $0.id < $1.id : $0.drawnStart < $1.drawnStart
        }
        if previous.isEmpty {
            // With no fixed occupants, sorted newcomers only need each row's
            // final endpoint. Retained layouts below must also search gaps.
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
        let retained = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.row) })
        var occupied: [[ClosedRange<Int64>]] = []
        for index in result.indices {
            guard let row = retained[result[index].id] else { continue }
            result[index].row = row
            while occupied.count <= row { occupied.append([]) }
            occupied[row].append(result[index].drawnStart...result[index].drawnEnd)
        }
        for index in result.indices {
            guard retained[result[index].id] == nil else { continue }
            let extent = result[index].drawnStart...result[index].drawnEnd
            if let row = occupied.firstIndex(where: { ranges in
                // Sorted extents let the common append case use only the last
                // bound; an earlier newcomer checks its two neighboring ranges.
                let position = insertionPosition(of: extent.lowerBound, in: ranges)
                return (position == 0 || ranges[position - 1].upperBound < extent.lowerBound)
                    && (position == ranges.count || ranges[position].lowerBound > extent.upperBound)
            }) {
                result[index].row = row
                let position = insertionPosition(of: extent.lowerBound, in: occupied[row])
                occupied[row].insert(extent, at: position)
            } else {
                result[index].row = occupied.count
                occupied.append([extent])
            }
        }
        return result
    }

    private static func insertionPosition(of start: Int64, in ranges: [ClosedRange<Int64>]) -> Int {
        if let last = ranges.last, last.lowerBound <= start { return ranges.count }
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = low + (high - low) / 2
            if ranges[middle].lowerBound < start { low = middle + 1 }
            else { high = middle }
        }
        return low
    }

    private func restoreSuccessfulView(for error: RegionalLoadError, generation: UInt64) {
        var restored = presentation
        restored.target = lastSuccessful?.target
        restored.alignments = lastSuccessful?.alignments ?? []
        restored.rowCount = lastSuccessful?.rowCount ?? 0
        restored.verticalOffset = 0
        restored.message = lastSuccessful?.message ?? "Enter a genomic interval"
        restored.isLoading = false
        restored.isDownsampled = lastSuccessful?.isDownsampled ?? false
        restored.isAlignmentSuppressed = lastSuccessful?.isAlignmentSuppressed ?? false
        if let target = restored.target, !restored.isAlignmentSuppressed {
            // Restoration already holds a complete result, even if intervening
            // partial queries evicted its historical cache entries.
            regionalData.insert(lastSuccessfulCandidates, for: target, keeping: target)
        }
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
            dragOrigin = nil
            deferredRegionalCompletion = nil
            lastSuccessful = nil
            lastSuccessfulCandidates = []
            sampling.seed = samplingSeed()
            regionalData = RegionalData()
            draftGeneration = nil
            presentation = ViewerPresentation()
            presentation.bamURL = file.url
            presentation.indexURL = file.indexURL
            presentation.references = file.references
            presentation.windowTitle = "\(url.lastPathComponent) — bamdalf"
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
