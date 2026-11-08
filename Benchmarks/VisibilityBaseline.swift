import AppKit
import BamdalfKit
import Darwin
import Foundation

/// One interval per process. The shell runner supplies process peak RSS through
/// macOS /usr/bin/time -l, including startup, loading, rendering, and PNG export.
@main
struct VisibilityBaseline {
    actor QueryWork {
        private var calls = 0
        private var eligibleRecords = 0
        private var milliseconds = 0.0

        func record(count: Int, milliseconds: Double) {
            calls += 1
            eligibleRecords += count
            self.milliseconds += milliseconds
        }

        func snapshot() -> (calls: Int, eligibleRecords: Int, milliseconds: Double) {
            (calls, eligibleRecords, milliseconds)
        }
    }

    struct GroupIdentity: Hashable {
        let readGroup: String?
        let name: String
        let unnamedRecord: UInt64?

        init(_ alignment: Alignment) {
            readGroup = alignment.name == "*" ? nil : alignment.readGroup
            name = alignment.name
            unnamedRecord = alignment.name == "*" ? alignment.id : nil
        }
    }

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await measure(arguments: Array(CommandLine.arguments.dropFirst()))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("VisibilityBaseline: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        application.run()
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private static func wallSeconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    @MainActor
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView != nil { return scroll }
        for child in view.subviews {
            if let found = scrollView(in: child) { return found }
        }
        return nil
    }

    @MainActor
    private static func measure(arguments: [String]) async throws {
        guard (3...4).contains(arguments.count) else {
            throw Failure("usage: VisibilityBaseline BAM chr20:start-end OUTPUT_PREFIX [SAMPLING_GROUP_BUDGET]")
        }
        let budget = arguments.count == 4 ? Int(arguments[3]) : Int.max
        guard let budget, budget > 0 else { throw Failure("Sampling group budget must be a positive integer") }
        let bam = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let output = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let queryWork = QueryWork()
        let session = ViewerSession(loadRegion: { file, target in
            let start = wallSeconds()
            let records = try await file.alignments(in: target)
            await queryWork.record(count: records.count, milliseconds: (wallSeconds() - start) * 1000)
            return records
        }, alignmentVisibilityLimit: .max, samplingGroupBudget: budget, samplingSeed: { 42 })
        let controller = ViewerWindowController(session: session)
        guard let window = controller.window, let content = window.contentView else {
            throw Failure("Native viewer window is unavailable")
        }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.orderFront(nil)
        content.layoutSubtreeIfNeeded()
        // Let the real AppKit window complete initial layout before measuring.
        try await Task.sleep(for: .milliseconds(100))

        let openStart = wallSeconds()
        await session.openBAM(bam)
        let openMilliseconds = (wallSeconds() - openStart) * 1000
        guard session.presentation.bamURL != nil else {
            throw Failure(session.presentation.openError?.message ?? "BAM open did not complete; select exactly one sibling index")
        }
        session.editInterval(arguments[1])
        let queryCPUStart = cpuSeconds()
        let queryStart = wallSeconds()
        guard let task = session.submitInterval() else {
            throw Failure(session.presentation.intervalError ?? "Interval submission did not start a regional query")
        }
        await task.value
        content.layoutSubtreeIfNeeded()
        let queryMilliseconds = (wallSeconds() - queryStart) * 1000
        let queryCPUMilliseconds = (cpuSeconds() - queryCPUStart) * 1000
        let presentation = session.presentation
        guard !presentation.isLoading, presentation.regionalError == nil,
              let interval = presentation.target else {
            throw Failure(presentation.regionalError?.message ?? "Regional query did not complete")
        }
        guard !presentation.alignments.isEmpty else {
            throw Failure("No alignments: this baseline requires unsuppressed representative data")
        }
        guard let scroll = scrollView(in: content), let renderer = scroll.documentView else {
            throw Failure("Could not locate native alignment renderer through NSScrollView.documentView")
        }
        try await Task.sleep(for: .milliseconds(100))
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let visible = renderer.visibleRect
        guard visible.width > 0, visible.height > 0 else {
            throw Failure("Native alignment viewport has zero size")
        }
        let scale = window.backingScaleFactor
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(visible.width * scale)),
            pixelsHigh: Int(ceil(visible.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw Failure("Cannot allocate native renderer bitmap")
        }
        bitmap.size = visible.size
        let cg = bitmapContext.cgContext
        cg.scaleBy(x: scale, y: scale)
        if renderer.isFlipped {
            cg.translateBy(x: 0, y: visible.height)
            cg.scaleBy(x: 1, y: -1)
        }
        cg.translateBy(x: -visible.minX, y: -visible.minY)
        cg.clip(to: visible)
        let graphics = NSGraphicsContext(cgContext: cg, flipped: renderer.isFlipped)
        let iterations = 5
        var drawWall: [Double] = []
        var drawCPU: [Double] = []
        // Exercise the actual NSView override. No copied renderer, surrogate
        // shapes or separate sampling implementation are used by this harness.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            for _ in 0..<iterations {
                let cpuStart = cpuSeconds()
                let start = wallSeconds()
                renderer.draw(visible)
                cg.flush()
                drawWall.append((wallSeconds() - start) * 1000)
                drawCPU.append((cpuSeconds() - cpuStart) * 1000)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure("Cannot encode alignment renderer PNG")
        }
        let rendererPNG = output.path + ".alignments.png"
        try pixels.write(to: URL(fileURLWithPath: rendererPNG))

        // Supplementary native-content capture. Inspect before using: AppKit
        // cacheDisplay can omit layer-backed content on some OS versions.
        var contentPNG: String? = nil
        if let whole = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: whole)
            if let png = whole.representation(using: .png, properties: [:]) {
                contentPNG = output.path + ".content.png"
                try png.write(to: URL(fileURLWithPath: contentPNG!))
            }
        }
        let spans = presentation.alignments.map { $0.drawnEnd - $0.drawnStart + 1 }.sorted()
        let width = interval.end - interval.start + 1
        let work = await queryWork.snapshot()
        let result: [String: Any] = [
            "schema_version": 2,
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "bam": bam.path,
            "index": presentation.indexURL?.path ?? "",
            "interval": interval.formatted,
            "width_bases": width,
            "alignments": presentation.alignments.count,
            "retained_groups": Set(presentation.alignments.map(GroupIdentity.init)).count,
            "sampling_group_budget": budget,
            "sampling_seed": 42,
            "is_downsampled": presentation.isDownsampled,
            "regional_query_calls": work.calls,
            "queried_eligible_records": work.eligibleRecords,
            "regional_query_wall_ms": work.milliseconds,
            "rows": presentation.rowCount,
            "file_open_wall_ms": openMilliseconds,
            "query_pack_native_layout_wall_ms": queryMilliseconds,
            "query_pack_native_layout_cpu_ms": queryCPUMilliseconds,
            "renderer_draw_wall_ms": drawWall,
            "renderer_draw_cpu_ms": drawCPU,
            "renderer_draw_wall_mean_ms": drawWall.reduce(0, +) / Double(iterations),
            "renderer_draw_cpu_mean_ms": drawCPU.reduce(0, +) / Double(iterations),
            "viewport_width_points": visible.width,
            "viewport_height_points": visible.height,
            "viewport_origin_y_points": visible.minY,
            "document_height_points": renderer.bounds.height,
            "backing_scale": scale,
            "points_per_base": Double(visible.width) / Double(width),
            "median_drawn_span_bases": spans[spans.count / 2],
            "renderer_type": String(describing: type(of: renderer)),
            "renderer_png": rendererPNG,
            "supplementary_content_png": contentPNG ?? "",
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "processor_count": ProcessInfo.processInfo.processorCount,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "measurement_scope": "Fresh process and session, existing OS file caches uncontrolled; query includes packing and synchronous native controller layout; draw timing is visible-viewport bitmap CPU rasterization, excluding PNG encoding and compositor/presentation; process peak RSS supplied separately by macOS time -l includes all stages."
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: output.path + ".json"))
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
        window.orderOut(nil)
        withExtendedLifetime(controller) {}
    }
}
