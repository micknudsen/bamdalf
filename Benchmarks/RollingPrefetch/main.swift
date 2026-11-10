import AppKit
import BamdalfKit
import Darwin
import Foundation

@main
struct RollingPrefetch {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    struct Query: Codable {
        let kind: String
        let start: Int64
        let end: Int64
        let startedMS: Double
        var finishedMS: Double?
        var returnedRecords: Int?
        var outcome: String?
    }

    actor Trace {
        let origin = DispatchTime.now().uptimeNanoseconds
        var queries: [Query] = []

        func begin(_ kind: String, _ interval: GenomicInterval) -> Int {
            let id = queries.count
            queries.append(Query(kind: kind, start: interval.start, end: interval.end, startedMS: elapsed()))
            return id
        }

        func finish(_ id: Int, records: Int?, error: Error? = nil) {
            queries[id].finishedMS = elapsed()
            queries[id].returnedRecords = records
            queries[id].outcome = error.map {
                if $0 is CancellationError { return "canceled" }
                if $0 is RegionalQueryBudgetExceeded { return "budget" }
                return String(describing: $0)
            } ?? "complete"
        }

        func snapshot() -> [Query] { queries }
        func requiredCount() -> Int { queries.filter { $0.kind == "required" }.count }
        func idle() -> Bool {
            queries.allSatisfy { $0.finishedMS != nil } && elapsed() - (queries.compactMap(\.finishedMS).max() ?? 0) >= 100
        }
        private func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - origin) / 1_000_000 }
    }

    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await measure(Array(CommandLine.arguments.dropFirst()))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("RollingPrefetch: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        app.run()
    }

    @MainActor
    static func measure(_ args: [String]) async throws {
        guard args.count == 7, let fraction = Double(args[2]), let completeStart = Int64(args[3]),
              let completeEnd = Int64(args[4]), let panPeriod = Double(args[5]) else {
            throw Failure("usage: RollingPrefetch BAM INTERVAL REFILL_FRACTION_OR_MINUS_ONE COMPLETE_START COMPLETE_END PAN_PERIOD_MS OUTPUT_JSON")
        }
        let trace = Trace()
        let session = ViewerSession(prefetch: fraction < 0 ? .disabled : .init(refillFraction: fraction), loadRegion: { file, interval in
            let id = await trace.begin("required", interval)
            do {
                guard interval.start >= completeStart, interval.end <= completeEnd else { throw Failure("Required query exceeds complete extraction") }
                let records = try await file.alignments(in: interval)
                await trace.finish(id, records: records.count)
                return records
            } catch {
                await trace.finish(id, records: nil, error: error)
                throw error
            }
        }, samplingSeed: { 42 }, loadPrefetchRegion: { file, interval, budget in
            let id = await trace.begin("optional", interval)
            do {
                guard interval.start >= completeStart, interval.end <= completeEnd else { throw Failure("Optional query exceeds complete extraction") }
                let records = try await file.alignments(in: interval, budget: budget)
                await trace.finish(id, records: records.count)
                return records
            } catch {
                await trace.finish(id, records: nil, error: error)
                throw error
            }
        })
        let controller = ViewerWindowController(session: session)
        guard let window = controller.window, let content = window.contentView,
              let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first,
              let renderer = scroll.documentView else { throw Failure("Native viewer unavailable") }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.orderFront(nil)
        content.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        await session.openBAM(URL(fileURLWithPath: args[0]))
        guard session.presentation.bamURL != nil else { throw Failure("BAM open failed") }
        session.editInterval(args[1])
        let started = now()
        await session.submitInterval()?.value
        content.layoutSubtreeIfNeeded()
        try requireReady(session)
        let firstReady = now() - started
        let firstRaster = try raster(renderer, window: window)
        let firstTotal = now() - started
        let initial = session.presentation
        try await settle(trace)
        guard session.presentation.alignments == initial.alignments,
              session.presentation.target == initial.target else { throw Failure("Warmup changed stationary target") }

        var pans: [[String: Any]] = []
        for step in 0..<24 {
            let direction: PanDirection = (8..<16).contains(step) ? .left : .right
            let count = await trace.requiredCount()
            let start = now()
            let pending = session.pan(direction)
            let wasLoading = session.presentation.isLoading
            await pending?.value
            content.layoutSubtreeIfNeeded()
            try requireReady(session)
            let ready = now() - start
            let drawing = try raster(renderer, window: window)
            let elapsed = now() - start
            pans.append([
                "step": step, "direction": (8..<16).contains(step) ? "left" : "right",
                "start": session.presentation.target!.start, "end": session.presentation.target!.end,
                "ready_ms": ready, "raster_ms": drawing, "ready_and_raster_ms": elapsed,
                "was_loading": wasLoading, "required_queries": await trace.requiredCount() - count,
            ])
            try await pace(from: start, period: panPeriod)
        }

        // This route runs actual NSView pointer events. It does not wait for
        // optional work between frames, including at the direction reversal.
        try mouse(.leftMouseDown, fraction: 0.75, renderer: renderer, window: window)
        var frames: [[String: Any]] = []
        let positions = Array(1...8) + Array((0...7).reversed()) + Array(1...8) + Array((0...7).reversed())
        let dragInitial = session.presentation.target!
        for (index, position) in positions.enumerated() {
            let start = now()
            let fraction = 0.75 - Double(position) * 0.25 - 0.0025
            try mouse(.leftMouseDragged, fraction: fraction, renderer: renderer, window: window)
            content.layoutSubtreeIfNeeded()
            guard !session.presentation.isLoading, session.presentation.regionalError == nil else { throw Failure("Preview added loading/error presentation") }
            let drawing = try raster(renderer, window: window)
            frames.append([
                "frame": index, "quarter_width_displacement": position,
                "start": session.presentation.target!.start, "end": session.presentation.target!.end,
                "fractional_bases": session.presentation.previewOffsetInBases,
                "event_and_raster_ms": now() - start, "raster_ms": drawing,
                "displayed_records": session.presentation.alignments.count,
            ])
            try await pace(from: start, period: 33)
        }
        let releaseStart = now()
        let releaseRequired = await trace.requiredCount()
        try mouse(.leftMouseUp, fraction: 0.7475, renderer: renderer, window: window)
        await session.submitInterval()?.value
        content.layoutSubtreeIfNeeded()
        try requireReady(session)
        _ = try raster(renderer, window: window)
        let releaseElapsed = now() - releaseStart
        let releaseQueries = await trace.requiredCount() - releaseRequired
        try await settle(trace)
        let queries = await trace.snapshot()
        guard queries.allSatisfy({ $0.start >= completeStart && $0.end <= completeEnd }) else { throw Failure("Out-of-extraction query") }
        guard !queries.contains(where: { $0.outcome != "complete" && $0.outcome != "canceled" && !($0.kind == "optional" && $0.outcome == "budget") }) else { throw Failure("Unexpected query failure") }
        let result: [String: Any] = [
            "schema_version": 1, "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "bam": args[0], "initial_interval": args[1], "refill_fraction": fraction,
            "complete_start": completeStart, "complete_end": completeEnd,
            "first_ready_ms": firstReady, "first_raster_ms": firstRaster, "first_ready_and_raster_ms": firstTotal,
            "pan_period_ms": panPeriod, "drag_period_ms": 33, "pans": pans, "drag_frames": frames,
            "drag_initial_start": dragInitial.start, "drag_initial_end": dragInitial.end,
            "release_ready_and_raster_ms": releaseElapsed, "release_required_queries": releaseQueries,
            "required_queries": queries.filter { $0.kind == "required" }.count,
            "optional_queries": queries.filter { $0.kind == "optional" }.count,
            "optional_canceled": queries.filter { $0.kind == "optional" && $0.outcome == "canceled" }.count,
            "optional_budget_stops": queries.filter { $0.kind == "optional" && $0.outcome == "budget" }.count,
            "required_returned_records": queries.filter { $0.kind == "required" }.reduce(0) { $0 + ($1.returnedRecords ?? 0) },
            "optional_returned_records": queries.filter { $0.kind == "optional" }.reduce(0) { $0 + ($1.returnedRecords ?? 0) },
            "queries": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queries)),
            "boundary": "Production session and native NSView pointer events/layout plus visible-viewport bitmap raster. Excludes compositor presentation. Paced motion never awaits optional idle; only initial warming and final cleanup do. Returned records exclude records decoded and discarded by reader filtering/cancellation; no decoded-record or physical-I/O count is claimed."
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: args[6]))
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    @MainActor
    static func requireReady(_ session: ViewerSession) throws {
        guard !session.presentation.isLoading, session.presentation.regionalError == nil,
              !session.presentation.alignments.isEmpty else { throw Failure("Committed view did not become ready with records") }
    }

    static func pace(from start: Double, period: Double) async throws {
        let remaining = period - (now() - start)
        if remaining > 0 { try await Task.sleep(for: .milliseconds(remaining)) }
    }

    static func settle(_ trace: Trace) async throws {
        let start = now()
        while !(await trace.idle()) {
            guard now() - start < 30_000 else { throw Failure("Queries did not become idle") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    static func mouse(_ type: NSEvent.EventType, fraction: Double, renderer: NSView, window: NSWindow) throws {
        guard let event = NSEvent.mouseEvent(with: type,
                                             location: renderer.convert(NSPoint(x: renderer.bounds.width * fraction, y: renderer.bounds.minY + 8), to: nil),
                                             modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw Failure("Could not create native pointer event") }
        switch type {
        case .leftMouseDown: renderer.mouseDown(with: event)
        case .leftMouseDragged: renderer.mouseDragged(with: event)
        case .leftMouseUp: renderer.mouseUp(with: event)
        default: throw Failure("Unsupported pointer event")
        }
    }

    @MainActor
    static func raster(_ view: NSView, window: NSWindow) throws -> Double {
        let visible = view.visibleRect
        let scale = window.backingScaleFactor
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(ceil(visible.width * scale)), pixelsHigh: Int(ceil(visible.height * scale)),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw Failure("Could not create viewport raster") }
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: visible.height)
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: -visible.minX, y: -visible.minY)
        cg.clip(to: visible)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let start = now()
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.draw(visible)
            cg.flush()
        }
        NSGraphicsContext.restoreGraphicsState()
        return now() - start
    }
}
