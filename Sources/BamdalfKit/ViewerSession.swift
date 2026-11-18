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
    public var referenceURL: URL?
    public var referenceBases: ReferenceRegion?
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
    public var intervalEntryAvailable: Bool { bamURL != nil || referenceURL != nil }
    public var openError: FileOpenError?
    public var indexChoice: IndexChoice?
}

@MainActor
public final class ViewerSession {
    public private(set) var presentation = ViewerPresentation() {
        didSet { onPresentationChange?() }
    }
    public var onPresentationChange: (@MainActor () -> Void)?
    public private(set) var selectedReference: ReferenceBundle?
    private var previewRead: Task<Void, Never>?
    private var previewDemand: GenomicInterval?
    private var failedPreviews: [GenomicInterval] = []
    private var referenceNavigationGeneration: UInt64 = 0
    private var viewportWidth = 0.0
    private let loadReferenceRegion: @Sendable (ReferenceBundle, GenomicInterval) async throws -> Data
    private var bam: BAMFile?
    private var openingID = UUID()
    private var scrollGeneration: UInt64 = 0
    private var lastSuccessful: ViewerPresentation?
    private var lastSuccessfulRecords: [Alignment] = []
    private var lastSuccessfulCoverage: GenomicInterval?
    private var sampling: AlignmentSampling
    private let samplingSeed: @Sendable () -> UInt64
    private var editorGeneration: UInt64 = 0
    private var draftGeneration: UInt64?
    private var regionalRequestID = UUID()
    private var regionalTask: Task<Void, Never>?
    private var dragOrigin: ViewerPresentation?
    private var dragFraction = 0.0
    private var deferredRegionalCompletion: (@MainActor () -> Void)?
    private var regionalData = RegionalData()
    private let alignmentVisibilityLimit: Int64
    private let tailSearchMargin: Int64 = 250
    private let loadRegion: @Sendable (BAMFile, GenomicInterval) async throws -> [Alignment]
    private let prefetch: PrefetchConfiguration
    private let loadPrefetchRegion: @Sendable (BAMFile, GenomicInterval, RegionalQueryBudget) async throws -> [Alignment]
    private var prefetchTask: Task<Void, Never>?
    private var prefetchID = UUID()
    private struct PrefetchDemand {
        let required: GenomicInterval
        let desired: GenomicInterval
        let direction: PanDirection?
    }
    private var prefetchDemand: PrefetchDemand?
    private var prefetchMotionOrigin: GenomicInterval?
    private var requiredReadID: UUID?
    private var blockedPrefetch: [GenomicInterval] = []
    private var stoppedPrefetch = false
    private let loadFile: @Sendable (URL, URL) async throws -> BAMFile

    public init(prefetch: PrefetchConfiguration = .init(),
                loadBAM: (@Sendable (URL, URL) async throws -> BAMFile)? = nil,
                loadReferenceRegion: (@Sendable (ReferenceBundle, GenomicInterval) async throws -> Data)? = nil,
                loadRegion: (@Sendable (BAMFile, GenomicInterval) async throws -> [Alignment])? = nil,
                alignmentVisibilityLimit: Int64 = 10_000, samplingGroupBudget: Int = 2_000,
                samplingSeed: @escaping @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) },
                samplingPriority: (@Sendable (UInt64, [UInt8]) -> UInt64)? = nil,
                loadPrefetchRegion: (@Sendable (BAMFile, GenomicInterval, RegionalQueryBudget) async throws -> [Alignment])? = nil) {
        precondition(alignmentVisibilityLimit > 0)
        self.alignmentVisibilityLimit = alignmentVisibilityLimit
        self.sampling = AlignmentSampling(budget: samplingGroupBudget, priority: samplingPriority)
        self.samplingSeed = samplingSeed
        loadFile = loadBAM ?? BAMFile.open
        self.loadReferenceRegion = loadReferenceRegion ?? Self.readReference
        self.loadRegion = loadRegion ?? Self.readAlignments
        self.prefetch = prefetch
        self.loadPrefetchRegion = loadPrefetchRegion ?? Self.readAlignments
        regionalData = RegionalData(historicalLimit: prefetch.maximumBytes == 0 ? 8 : nil)
    }

    // Keep the default actor calls in the library. Swift 6.1 can emit a null
    // call target for these readers inside a public initializer's default arguments.
    private nonisolated static func readAlignments(_ bam: BAMFile, _ interval: GenomicInterval) async throws -> [Alignment] {
        try await bam.alignments(in: interval)
    }

    private nonisolated static func readAlignments(_ bam: BAMFile, _ interval: GenomicInterval,
                                                  _ budget: RegionalQueryBudget) async throws -> [Alignment] {
        try await bam.alignments(in: interval, budget: budget)
    }

    private nonisolated static func readReference(_ bundle: ReferenceBundle, _ interval: GenomicInterval) async throws -> Data {
        try await bundle.read(interval)
    }

    public func openReference(_ url: URL?) async {
        guard let url, bam == nil else { return }
        let request = UUID()
        openingID = request
        presentation.isOpening = true
        presentation.openError = nil
        presentation.indexChoice = nil
        defer { if openingID == request { presentation.isOpening = false } }
        do {
            let bundle = try await Task.detached { try ReferenceBundle(opening: url) }.value
            guard openingID == request, !Task.isCancelled else { return }
            let prior = (dragOrigin ?? presentation).target
            resetReferenceView()
            selectedReference = bundle
            var next = ViewerPresentation()
            next.referenceURL = bundle.url
            next.references = bundle.contigs.map { ReferenceSequence(name: $0.name, length: $0.length) }
            next.message = "Enter a genomic interval"
            next.sessionID = UUID()
            presentation = next
            if let prior, let contig = next.references.contig(named: prior.reference),
               prior.end <= contig.length {
                presentation.intervalText = prior.formatted
                await submitInterval()?.value
            }
        } catch {
            guard openingID == request else { return }
            presentation.openError = FileOpenError(fileURL: url, message: error.localizedDescription)
        }
    }

    public func closeReference() {
        guard selectedReference != nil else { return }
        openingID = UUID()
        resetReferenceView()
        selectedReference = nil
        presentation = ViewerPresentation()
    }

    private func resetReferenceView() {
        stopPreviewRead()
        failedPreviews.removeAll()
        regionalTask?.cancel()
        regionalTask = nil
        regionalRequestID = UUID()
        lastSuccessful = nil
        dragOrigin = nil
        deferredRegionalCompletion = nil
        draftGeneration = nil
    }

    @discardableResult
    public func setViewportWidth(_ width: Double) -> Task<Void, Never>? {
        guard width.isFinite, width >= 0, width != viewportWidth else { return nil }
        let previousWidth = viewportWidth
        viewportWidth = width
        guard let bundle = selectedReference, let target = (dragOrigin ?? presentation).target else { return nil }
        guard (target.referenceScale(in: previousWidth) == nil) != (target.referenceScale(in: width) == nil) else { return nil }
        _ = restoreDragOrigin()
        return loadReferenceTarget(target, from: bundle)
    }

    private func loadReferenceTarget(_ target: GenomicInterval, from bundle: ReferenceBundle) -> Task<Void, Never>? {
        regionalTask?.cancel()
        let request = UUID()
        regionalRequestID = request
        var next = presentation
        next.target = target
        next.message = ""
        next.regionalError = nil
        next.referenceBases = nil
        next.isLoading = target.referenceScale(in: viewportWidth) != nil
        presentation = next
        guard next.isLoading else {
            lastSuccessful = next
            regionalTask = nil
            return nil
        }
        let generation = referenceNavigationGeneration
        regionalTask = Task {
            let result: Result<ReferenceRegion, RegionalLoadError>
            do {
                let bases = try await loadReferenceRegion(bundle, target)
                result = .success(ReferenceRegion(interval: target, bases: bases))
            } catch {
                let message = (error as? RegionalLoadError)?.message ?? error.localizedDescription
                result = .failure(RegionalLoadError(interval: target, message: message))
            }
            await completeReferenceLoad(result, from: bundle, request: request, generation: generation)?.value
        }
        return regionalTask
    }

    private func completeReferenceLoad(_ result: Result<ReferenceRegion, RegionalLoadError>, from bundle: ReferenceBundle,
                                       request: UUID, generation: UInt64) -> Task<Void, Never>? {
        guard regionalRequestID == request else { return nil }
        if dragOrigin != nil {
            deferredRegionalCompletion = { [weak self] in
                _ = self?.completeReferenceLoad(result, from: bundle, request: request, generation: generation)
            }
            return nil
        }
        regionalTask = nil
        switch result {
        case .success(let region):
            // A successful required retry establishes that the failed range is readable.
            failedPreviews.removeAll {
                $0.reference.utf8.elementsEqual(region.interval.reference.utf8)
                    && region.interval.start <= $0.start && region.interval.end >= $0.end
            }
            var next = presentation
            next.referenceBases = region
            next.isLoading = false
            presentation = next
            lastSuccessful = next
        case .failure(let error):
            if let prior = lastSuccessful, let target = prior.target,
               prior.referenceBases == nil, target.referenceScale(in: viewportWidth) != nil {
                if target != error.interval {
                    // The previous overview became detailed while the new target was
                    // loading. Retrieve its newly visible bases before presenting the alert.
                    regionalTask = Task {
                        let bases = try? await loadReferenceRegion(bundle, target)
                        guard regionalRequestID == request else { return }
                        if let bases {
                            lastSuccessful?.referenceBases = ReferenceRegion(interval: target, bases: bases)
                        } else if target.referenceScale(in: viewportWidth) != nil {
                            lastSuccessful = nil
                        }
                        await completeReferenceLoad(result, from: bundle, request: request, generation: generation)?.value
                    }
                    return regionalTask
                }
                // The failed read was the first detail requested for this overview.
                lastSuccessful = nil
            }
            restoreSuccessfulView(for: error, generation: generation)
        }
        return nil
    }

    public func editInterval(_ text: String) {
        guard !text.utf8.elementsEqual(presentation.intervalText.utf8) else { return }
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
        dragFraction = 0
    }

    /// Pointer displacement as a fraction of the viewport width, from pointer-down.
    @discardableResult
    public func previewAlignmentDrag(horizontalFraction: Double) -> Task<Void, Never>? {
        guard horizontalFraction.isFinite else { return nil }
        dragFraction = horizontalFraction
        let previous = presentation.target
        let previousOffset = presentation.previewOffsetInBases
        refreshDragPreview()
        if presentation.target != previous || presentation.previewOffsetInBases != previousOffset {
            startPrefetch(rollingFrom: previous)
        }
        return previewRead
    }

    private func refreshDragPreview() {
        guard let origin = dragOrigin, let target = origin.target,
              let reference = presentation.references.contig(named: target.reference) else { return }
        let minimum = 1 - target.start
        let maximum = reference.length - target.end
        let exactShift = min(Double(maximum), max(Double(minimum), -dragFraction * Double(target.end - target.start + 1)))
        let displacement = exactShift.rounded(.toNearestOrAwayFromZero)
        let shift = displacement <= Double(minimum) ? minimum
            : displacement >= Double(maximum) ? maximum : Int64(displacement)
        let preview = GenomicInterval(reference: target.reference, start: target.start + shift, end: target.end + shift)
        let remainder = exactShift - Double(shift)
        let visibleBases = Self.fractionalVisibleInterval(for: preview, offset: remainder, referenceLength: reference.length)
        var next = presentation
        next.target = preview
        next.previewOffsetInBases = remainder
        if let bundle = selectedReference {
            next.isLoading = false
            let cached = [next.referenceBases, origin.referenceBases].compactMap { $0 }.first {
                $0.interval.start <= visibleBases.start && $0.interval.end >= visibleBases.end
            }
            if let cached { next.referenceBases = cached }
            presentation = next
            if cached == nil && target.referenceScale(in: viewportWidth) != nil {
                readPreview(visibleBases, from: bundle)
            } else {
                stopPreviewRead()
            }
            return
        }
        let available = regionalData.available(for: requiredInterval(for: visibleBases))
        let selected = sampling.select(origin.isAlignmentSuppressed ? [] : RegionalData.visible(available.records, in: visibleBases))
        next.alignments = Self.pack(selected.records, retaining: presentation.alignments)
        next.isDownsampled = selected.isDownsampled
        next.rowCount = max(presentation.rowCount, (next.alignments.map(\.row).max() ?? -1) + 1)
        next.isLoading = false
        presentation = next
    }

    // Coalesce pointer motion to the latest visible interval while a bounded
    // optional read is running. A failed preview never completes a committed load.
    private func readPreview(_ interval: GenomicInterval, from bundle: ReferenceBundle) {
        guard previewDemand != interval else { return }
        previewDemand = interval
        guard previewRead == nil else { return }
        previewRead = Task {
            while !Task.isCancelled, let wanted = previewDemand {
                guard failedPreviews.count < 64,
                      !failedPreviews.contains(where: { $0.distance(to: wanted) == 0 }) else { break }
                do {
                    let bases = try await loadReferenceRegion(bundle, wanted)
                    guard !Task.isCancelled else { return }
                    if previewDemand == wanted { presentation.referenceBases = ReferenceRegion(interval: wanted, bases: bases) }
                } catch {
                    guard !Task.isCancelled else { return }
                    failedPreviews.append(wanted)
                }
                if previewDemand == wanted { break }
            }
            if !Task.isCancelled { previewRead = nil }
        }
    }

    private func stopPreviewRead() {
        previewRead?.cancel()
        previewRead = nil
        previewDemand = nil
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
            return submitInterval(preservingPanContinuity: true, prefetchAfterLoad: false)
        }
        let task = regionalTask
        restored.completion?()
        return regionalTask ?? task
    }

    private func restoreDragOrigin() -> (origin: ViewerPresentation, completion: (@MainActor () -> Void)?)? {
        guard var origin = dragOrigin else { return nil }
        stopPreviewRead()
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
              let reference = presentation.references.contig(named: target.reference) else { return nil }
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
        return submitInterval(preservingPanContinuity: true, prefetchAfterLoad: false)
    }

    /// Halve (rounding up) or double width, breaking center ties toward lower coordinates.
    @discardableResult
    public func zoom(_ direction: ZoomDirection) -> Task<Void, Never>? {
        guard let target = presentation.target,
              let reference = presentation.references.contig(named: target.reference) else { return nil }
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
              let reference = presentation.references.contig(named: target.reference) else { return nil }
        let width = target.end - target.start + 1
        let newWidth = direction.resizedWidth(width, maximum: reference.length)
        guard newWidth != width else { return nil }
        let position = min(1, max(0, fraction)) * Double(width)
        let offset = position >= Double(width - 1) ? width - 1 : Int64(position)
        let locus = target.start + offset
        let start = min(max(1, locus - newWidth / 2), reference.length - newWidth + 1)
        presentation.intervalText = GenomicInterval(reference: target.reference,
                                                    start: start, end: start + (newWidth - 1)).formatted
        return submitInterval(preservingPanContinuity: true, prefetchAfterLoad: true)
    }

    @discardableResult
    public func submitInterval() -> Task<Void, Never>? {
        submitInterval(preservingPanContinuity: false, prefetchAfterLoad: true)
    }

    private func requiredInterval(for visible: GenomicInterval) -> GenomicInterval {
        let length = presentation.references.contig(named: visible.reference)!.length
        return GenomicInterval(reference: visible.reference,
                               start: visible.start - min(tailSearchMargin, visible.start - 1),
                               end: visible.end + min(tailSearchMargin, length - visible.end))
    }

    private var committedRequired: GenomicInterval? {
        let committed = dragOrigin ?? presentation
        guard let target = committed.target, !committed.isAlignmentSuppressed else { return nil }
        return requiredInterval(for: target)
    }

    private func admit(_ records: [Alignment], for interval: GenomicInterval) {
        let refreshPreview = dragOrigin != nil && previewRequired.map {
            !regionalData.missingCoverage(for: $0).isEmpty
        } == true
        let required = committedRequired
        regionalData.insert(records, for: interval, keeping: required ?? interval)
        if prefetch.maximumBytes > 0 {
            regionalData.trimOptional(keeping: required, recovery: lastSuccessfulCoverage, maximumBytes: prefetch.maximumBytes)
        }
        if refreshPreview { refreshDragPreview() }
    }

    private var previewRequired: GenomicInterval? {
        guard let target = presentation.target, !presentation.isAlignmentSuppressed else { return nil }
        let length = presentation.references.contig(named: target.reference)!.length
        let visible = Self.fractionalVisibleInterval(for: target, offset: presentation.previewOffsetInBases, referenceLength: length)
        return requiredInterval(for: visible)
    }

    private static func fractionalVisibleInterval(for target: GenomicInterval, offset: Double,
                                                 referenceLength: Int64) -> GenomicInterval {
        GenomicInterval(reference: target.reference,
                        start: offset < 0 ? max(1, target.start - 1) : target.start,
                        end: offset > 0 && target.end < referenceLength ? target.end + 1 : target.end)
    }

    private func trimOptional() {
        if prefetch.maximumBytes > 0 {
            regionalData.trimOptional(keeping: committedRequired, recovery: lastSuccessfulCoverage,
                                      maximumBytes: prefetch.maximumBytes)
        }
    }

    private func retirePrefetch() {
        prefetchID = UUID()
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchDemand = nil
    }

    private func suppressPrefetch(in interval: GenomicInterval) {
        blockedPrefetch.append(interval)
        // Failed reads and unretainable results share a bounded quiet backoff.
        // Required loads never consult it and may retry these ranges normally.
        if blockedPrefetch.count >= 64 { stoppedPrefetch = true }
    }

    /// Initial/jump/zoom fills establish both buffers. Rolling motion refreshes
    /// the latest demand only when a completed R-edge buffer runs low.
    private func startPrefetch(rollingFrom previous: GenomicInterval? = nil) {
        guard prefetch.maximumBytes > 0, !stoppedPrefetch, requiredReadID == nil,
              !presentation.isLoading, let bam, let target = presentation.target,
              !presentation.isAlignmentSuppressed else { return }
        let required = previewRequired!
        let buffer = max(target.end - target.start + 1, tailSearchMargin)
        let length = presentation.references.contig(named: target.reference)!.length
        let desired = GenomicInterval(reference: target.reference,
                                       start: required.start - min(buffer, required.start - 1),
                                       end: required.end + min(buffer, length - required.end))
        let direction: PanDirection? = previous.flatMap {
            guard $0.reference == target.reference, $0.start != target.start else { return nil }
            return target.start > $0.start ? .right : .left
        }
        if previous != nil {
            let threshold = Int64(Double(buffer) * prefetch.refillFraction)
            guard regionalData.missingCoverage(for: desired).contains(where: {
                max(0, $0.distance(to: required) - 1) <= threshold
            }) else { return }
        }
        prefetchDemand = PrefetchDemand(required: required, desired: desired, direction: direction)
        // A useful in-flight chunk can complete while motion coalesces into
        // this latest demand. Foreground reads retire the task separately.
        guard prefetchTask == nil else { return }
        let id = prefetchID
        prefetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { if prefetchID == id { prefetchTask = nil } }
            var attempted: [GenomicInterval] = []
            // Even failed/evicted chunks consume an attempt. This bounds work
            // without ever representing partial results as completed coverage.
            while prefetchID == id, !Task.isCancelled, !stoppedPrefetch, attempted.count < 80 {
                guard let demand = prefetchDemand else { break }
                let required = demand.required
                let missing = regionalData.missingCoverage(for: demand.desired)
                let candidates = missing.flatMap { Self.subtract(attempted + blockedPrefetch, from: $0) }
                guard let gap = candidates.min(by: {
                    let first = $0.distance(to: required), second = $1.distance(to: required)
                    if first != second { return first < second }
                    return demand.direction == .right ? $0.start > $1.start : $0.start < $1.start
                }) else { break }
                let interval: GenomicInterval
                if gap.start <= required.end && gap.end >= required.start {
                    let start = max(gap.start, required.start)
                    interval = GenomicInterval(reference: gap.reference, start: start,
                                                end: min(required.end, start + min(prefetch.chunkBases - 1, gap.end - start)))
                } else if gap.end < required.start {
                    interval = GenomicInterval(reference: gap.reference,
                                                start: max(gap.start, gap.end - min(prefetch.chunkBases - 1, gap.end - gap.start)), end: gap.end)
                } else {
                    interval = GenomicInterval(reference: gap.reference, start: gap.start,
                                                end: gap.start + min(prefetch.chunkBases - 1, gap.end - gap.start))
                }
                attempted.append(interval)
                do {
                    let budget = RegionalQueryBudget(maximumRecords: prefetch.maximumQueryRecords,
                                                     maximumBytes: min(prefetch.maximumQueryBytes, prefetch.maximumBytes))
                    let records = try await loadPrefetchRegion(bam, interval, budget)
                    guard self.bam === bam, prefetchID == id, !Task.isCancelled else { break }
                    admit(records, for: interval)
                    // Remember failed retention across motion updates, not
                    // just within this task. Otherwise each fractional pointer
                    // change can repeatedly read the same unretainable chunk.
                    if !regionalData.missingCoverage(for: interval).isEmpty {
                        suppressPrefetch(in: interval)
                        break
                    }
                } catch is CancellationError {
                    break
                } catch {
                    guard self.bam === bam, prefetchID == id, !Task.isCancelled else { break }
                    suppressPrefetch(in: interval)
                }
                await Task.yield()
            }
        }
    }

    private static func subtract(_ exclusions: [GenomicInterval], from interval: GenomicInterval) -> [GenomicInterval] {
        exclusions.reduce([interval]) { remaining, excluded in
            remaining.flatMap { $0.subtracting(excluded) }
        }
    }

    private func submitInterval(preservingPanContinuity: Bool, prefetchAfterLoad: Bool) -> Task<Void, Never>? {
        guard presentation.intervalEntryAvailable else { return nil }
        do {
            let target = try GenomicInterval.parse(presentation.intervalText, references: presentation.references)
            if let restored = restoreDragOrigin(), target == restored.origin.target {
                restored.completion?()
            }
            draftGeneration = nil
            presentation.intervalText = target.formatted
            presentation.intervalError = nil
            if target == presentation.target { return regionalTask }
            if let selectedReference {
                referenceNavigationGeneration = editorGeneration
                return loadReferenceTarget(target, from: selectedReference)
            }
            guard let bam else { return nil }
            if prefetchAfterLoad { retirePrefetch() }
            regionalTask?.cancel()
            let requestID = UUID()
            regionalRequestID = requestID
            presentation.regionalError = nil
            let generation = editorGeneration
            let initialScrollGeneration = scrollGeneration
            let suppressed = target.end - target.start + 1 > alignmentVisibilityLimit
            let previous = presentation.target
            prefetchMotionOrigin = prefetchAfterLoad ? nil : previous
            let continuous = !suppressed && !presentation.isAlignmentSuppressed && previous?.reference == target.reference
                && (preservingPanContinuity || (previous!.start <= target.end && previous!.end >= target.start))
            let required = requiredInterval(for: target)
            if prefetch.maximumBytes > 0 {
                regionalData.trimOptional(keeping: suppressed ? nil : required, recovery: lastSuccessfulCoverage,
                                          maximumBytes: prefetch.maximumBytes)
            }
            let available = regionalData.available(for: required)
            if suppressed || !available.missing.isEmpty { retirePrefetch() }
            var next = presentation
            next.target = target
            next.message = suppressed ? "Zoom in to see alignments" : ""
            next.isLoading = !suppressed && !available.missing.isEmpty
            next.isAlignmentSuppressed = suppressed
            let selected = sampling.select(suppressed ? [] : RegionalData.visible(available.records, in: target))
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
                lastSuccessfulRecords = []
                lastSuccessfulCoverage = nil
                trimOptional()
                return nil
            }
            if available.missing.isEmpty {
                regionalTask = nil
                lastSuccessfulRecords = available.records
                lastSuccessfulCoverage = required
                lastSuccessful = presentation
                trimOptional()
                startPrefetch(rollingFrom: prefetchMotionOrigin)
                return nil
            }
            requiredReadID = requestID
            regionalTask = Task {
                defer {
                    if requiredReadID == requestID {
                        requiredReadID = nil
                        startPrefetch(rollingFrom: dragOrigin?.target ?? prefetchMotionOrigin)
                    }
                }
                do {
                    var records = available.records
                    for (index, missing) in available.missing.enumerated() {
                        let loaded = try await loadRegion(bam, missing)
                        guard self.bam === bam else { return }
                        admit(loaded, for: missing)
                        guard regionalRequestID == requestID else { return }
                        records = RegionalData.eligible(records + loaded, for: required)
                        if dragOrigin == nil && index + 1 < available.missing.count {
                            let selected = sampling.select(RegionalData.visible(records, in: target))
                            presentation.alignments = Self.pack(selected.records, retaining: presentation.alignments)
                            presentation.isDownsampled = selected.isDownsampled
                            let requiredRows = (presentation.alignments.map(\.row).max() ?? -1) + 1
                            presentation.rowCount = continuous || scrollGeneration != initialScrollGeneration
                                ? max(presentation.rowCount, requiredRows) : requiredRows
                        }
                    }
                    admit(records, for: required)
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
        if requiredReadID == requestID { requiredReadID = nil }
        if dragOrigin != nil {
            deferredRegionalCompletion = { [weak self] in
                self?.completeRegionalLoad(result, requestID: requestID, generation: generation,
                                           initialScrollGeneration: initialScrollGeneration, continuous: continuous)
            }
            startPrefetch(rollingFrom: dragOrigin?.target)
            return
        }
        switch result {
        case .success(let records):
            let target = presentation.target!
            let selected = sampling.select(RegionalData.visible(records, in: target))
            presentation.alignments = Self.pack(selected.records, retaining: presentation.alignments)
            presentation.isDownsampled = selected.isDownsampled
            lastSuccessfulRecords = records
            lastSuccessfulCoverage = requiredInterval(for: target)
            let requiredRows = (presentation.alignments.map(\.row).max() ?? -1) + 1
            presentation.rowCount = continuous || scrollGeneration != initialScrollGeneration
                ? max(presentation.rowCount, requiredRows) : requiredRows
            presentation.isLoading = false
            lastSuccessful = presentation
            trimOptional()
            startPrefetch(rollingFrom: prefetchMotionOrigin)
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
        restored.referenceBases = lastSuccessful?.referenceBases
        restored.target = lastSuccessful?.target
        restored.alignments = lastSuccessful?.alignments ?? []
        restored.rowCount = lastSuccessful?.rowCount ?? 0
        restored.verticalOffset = 0
        restored.message = lastSuccessful?.message ?? "Enter a genomic interval"
        restored.isLoading = false
        restored.isDownsampled = lastSuccessful?.isDownsampled ?? false
        restored.isAlignmentSuppressed = lastSuccessful?.isAlignmentSuppressed ?? false
        if let coverage = lastSuccessfulCoverage, !restored.isAlignmentSuppressed {
            // Restoration already holds a complete result, even if intervening
            // partial queries evicted its historical cache entries.
            regionalData.insert(lastSuccessfulRecords, for: coverage, keeping: coverage)
        }
        if draftGeneration == nil || draftGeneration! <= generation {
            restored.intervalText = restored.target?.formatted ?? ""
            restored.intervalError = nil
            draftGeneration = nil
        }
        restored.regionalError = RegionalLoadError(id: regionalRequestID, interval: error.interval, message: error.message)
        presentation = restored
        trimOptional()
    }

    public func dismissRegionalError(_ id: UUID) {
        guard presentation.regionalError?.id == id else { return }
        presentation.regionalError = nil
    }

    public func dismissOpenError() {
        presentation.openError = nil
    }

    public func openBAM(_ url: URL?) async {
        guard let url, selectedReference == nil else { return }
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
            retirePrefetch()
            regionalTask?.cancel()
            blockedPrefetch = []
            stoppedPrefetch = false
            bam = file
            regionalRequestID = UUID()
            regionalTask = nil
            requiredReadID = nil
            prefetchMotionOrigin = nil
            dragOrigin = nil
            dragFraction = 0
            deferredRegionalCompletion = nil
            lastSuccessful = nil
            lastSuccessfulRecords = []
            lastSuccessfulCoverage = nil
            sampling.seed = samplingSeed()
            regionalData = RegionalData(historicalLimit: prefetch.maximumBytes == 0 ? 8 : nil)
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
