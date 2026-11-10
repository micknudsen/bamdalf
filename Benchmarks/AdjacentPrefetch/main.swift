import AppKit
import BamdalfKit
import Darwin
import Foundation

/// Fresh-process native measurements. Timing sleeps settle the window/cache
/// only; the correctness suite uses controlled completions instead.
@main
struct AdjacentPrefetch {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    struct QueryEvent: Codable {
        let kind: String
        let interval: String
        let start: Int64
        let end: Int64
        let startedMilliseconds: Double
        var finishedMilliseconds: Double?
        var records: Int?
        var outcome: String?
    }

    actor QueryTrace {
        let origin = DispatchTime.now().uptimeNanoseconds
        var events: [QueryEvent] = []

        func begin(_ kind: String, _ interval: GenomicInterval) -> Int {
            let index = events.count
            events.append(QueryEvent(kind: kind, interval: interval.formatted,
                                     start: interval.start, end: interval.end,
                                     startedMilliseconds: milliseconds()))
            return index
        }

        func finish(_ index: Int, records: Int?, outcome: String) {
            events[index].finishedMilliseconds = milliseconds()
            events[index].records = records
            events[index].outcome = outcome
        }

        func snapshot() -> [QueryEvent] { events }

        func isIdle(milliseconds quiet: Double) -> Bool {
            !events.contains { $0.finishedMilliseconds == nil }
                && milliseconds() - (events.last?.finishedMilliseconds ?? 0) >= quiet
        }

        private func milliseconds() -> Double {
            Double(DispatchTime.now().uptimeNanoseconds - origin) / 1_000_000
        }
    }

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await measure(Array(CommandLine.arguments.dropFirst()))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("AdjacentPrefetch: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        application.run()
    }

    static func milliseconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
    }

    @MainActor
    static func nativeRenderer(_ view: NSView) -> NSView? {
        if let scroll = view as? NSScrollView { return scroll.documentView }
        return view.subviews.lazy.compactMap { nativeRenderer($0) }.first
    }

    @MainActor
    static func raster(_ view: NSView, window: NSWindow) throws -> Double {
        let visible = view.visibleRect
        let scale = window.backingScaleFactor
        guard visible.width > 0, visible.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(ceil(visible.width * scale)),
                                            pixelsHigh: Int(ceil(visible.height * scale)),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw Failure("Could not create native viewport raster")
        }
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        if view.isFlipped {
            cg.translateBy(x: 0, y: visible.height)
            cg.scaleBy(x: 1, y: -1)
        }
        cg.translateBy(x: -visible.minX, y: -visible.minY)
        cg.clip(to: visible)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: view.isFlipped)
        let start = milliseconds()
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.draw(visible)
            cg.flush()
        }
        let elapsed = milliseconds() - start
        NSGraphicsContext.restoreGraphicsState()
        return elapsed
    }

    @MainActor
    static func settle(_ trace: QueryTrace) async throws {
        let start = milliseconds()
        while !(await trace.isIdle(milliseconds: 100)) {
            guard milliseconds() - start < 30_000 else { throw Failure("Queries did not become idle") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    static func measure(_ arguments: [String]) async throws {
        guard arguments.count == 8 || arguments.count == 10 else {
            throw Failure("usage: AdjacentPrefetch BAM INTERVAL enabled|disabled CHUNK_BASES CACHE_BYTES QUERY_BYTES QUERY_RECORDS OUTPUT_JSON [interrupt|drain JUMP_INTERVAL]")
        }
        guard let chunk = Int64(arguments[3]), let cacheBytes = Int(arguments[4]),
              let queryBytes = Int(arguments[5]), let queryRecords = Int(arguments[6]) else {
            throw Failure("Invalid numeric configuration")
        }
        let enabled = arguments[2] == "enabled"
        let trace = QueryTrace()
        let configuration: PrefetchConfiguration = enabled
            ? .init(maximumBytes: cacheBytes, maximumQueryBytes: queryBytes,
                    maximumQueryRecords: queryRecords, chunkBases: chunk)
            : .disabled
        let session = ViewerSession(prefetch: configuration, loadRegion: { file, interval in
            let index = await trace.begin("required", interval)
            do {
                let records = try await file.alignments(in: interval)
                await trace.finish(index, records: records.count, outcome: "complete")
                return records
            } catch {
                await trace.finish(index, records: nil, outcome: String(describing: error))
                throw error
            }
        }, samplingSeed: { 42 }, loadPrefetchRegion: { file, interval, budget in
            let index = await trace.begin("optional", interval)
            do {
                let records = try await file.alignments(in: interval, budget: budget)
                await trace.finish(index, records: records.count, outcome: "complete")
                return records
            } catch {
                await trace.finish(index, records: nil, outcome: error is CancellationError ? "canceled" : String(describing: error))
                throw error
            }
        })
        if arguments.count == 10 {
            #if ADJACENT_PREFETCH_PROBE
            await session.openBAM(URL(fileURLWithPath: arguments[0]))
            guard session.presentation.bamURL != nil else {
                throw Failure(session.presentation.openError?.message ?? "BAM open failed")
            }
            try await interruption(session, trace: trace, arguments: arguments)
            return
            #else
            throw Failure("Actual-read probe mode requires the archived instrumented snapshot build")
            #endif
        }
        let controller = ViewerWindowController(session: session)
        guard let window = controller.window, let content = window.contentView else {
            throw Failure("Native viewer window is unavailable")
        }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.orderFront(nil)
        content.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        await session.openBAM(URL(fileURLWithPath: arguments[0]))
        guard session.presentation.bamURL != nil else {
            throw Failure(session.presentation.openError?.message ?? "BAM open failed")
        }
        session.editInterval(arguments[1])
        let firstStart = milliseconds()
        await session.submitInterval()?.value
        content.layoutSubtreeIfNeeded()
        let readyMilliseconds = milliseconds() - firstStart
        guard !session.presentation.isLoading, session.presentation.regionalError == nil,
              let renderer = nativeRenderer(content), !session.presentation.alignments.isEmpty else {
            throw Failure("Initial target did not become ready with a native renderer")
        }
        let initial = session.presentation
        let firstRasterMilliseconds = try raster(renderer, window: window)
        let readyAndRasterMilliseconds = milliseconds() - firstStart
        try await settle(trace)
        let prefetched = await trace.snapshot()
        guard session.presentation.target == initial.target,
              session.presentation.alignments == initial.alignments,
              session.presentation.rowCount == initial.rowCount,
              session.presentation.isDownsampled == initial.isDownsampled,
              !session.presentation.isLoading, session.presentation.regionalError == nil else {
            throw Failure("Optional loading changed the stationary view")
        }
        let requiredBeforePan = prefetched.filter { $0.kind == "required" }.count
        let panStart = milliseconds()
        await session.pan(.right)?.value
        content.layoutSubtreeIfNeeded()
        let panRasterMilliseconds = try raster(renderer, window: window)
        let panReadyAndRasterMilliseconds = milliseconds() - panStart
        let afterPan = await trace.snapshot()
        let eventData = try JSONEncoder().encode(afterPan)
        let result: [String: Any] = [
            "schema_version": 1,
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "bam": arguments[0], "interval": arguments[1], "enabled": enabled,
            "chunk_bases": chunk, "maximum_cache_bytes": cacheBytes,
            "maximum_query_bytes": queryBytes, "maximum_query_records": queryRecords,
            "first_ready_ms": readyMilliseconds, "first_raster_ms": firstRasterMilliseconds,
            "first_ready_and_raster_ms": readyAndRasterMilliseconds,
            "pan_ready_and_raster_ms": panReadyAndRasterMilliseconds,
            "pan_raster_ms": panRasterMilliseconds,
            "pan_required_queries": afterPan.filter { $0.kind == "required" }.count - requiredBeforePan,
            "displayed_records": initial.alignments.count, "rows": initial.rowCount,
            "is_downsampled": initial.isDownsampled,
            "optional_query_count": prefetched.filter { $0.kind == "optional" }.count,
            "optional_returned_records": prefetched.filter { $0.kind == "optional" }.compactMap(\.records).reduce(0, +),
            "optional_errors": prefetched.filter { $0.kind == "optional" && $0.outcome != "complete" }.count,
            "queries": try JSONSerialization.jsonObject(with: eventData),
            "renderer_type": String(describing: type(of: renderer)),
            "viewport_width_points": renderer.visibleRect.width,
            "viewport_height_points": renderer.visibleRect.height,
            "backing_scale": window.backingScaleFactor,
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "measurement_scope": "Fresh process/session; OS caches uncontrolled. Submit-to-ready includes native controller layout; submit-to-ready-and-raster additionally includes first actual viewport NSView.draw bitmap raster, excluding compositor presentation. Optional completion is followed by one half-width right pan. Process peak RSS is collected externally."
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: arguments[7]))
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
        window.orderOut(nil)
        withExtendedLifetime(controller) {}
    }

    #if ADJACENT_PREFETCH_PROBE
    @MainActor
    static func interruption(_ session: ViewerSession, trace: QueryTrace, arguments: [String]) async throws {
        let signal = AsyncStream<Void>.makeStream()
        AdjacentPrefetchProbe.arm { signal.continuation.yield(()) }
        let interrupts = arguments[8] == "interrupt"
        let jump = Task { @MainActor () throws -> [String: Double] in
            for await _ in signal.stream { break }
            guard interrupts else { return [:] }
            let issued = milliseconds()
            session.editInterval(arguments[9])
            await session.submitInterval()?.value
            guard !session.presentation.isLoading, session.presentation.regionalError == nil,
                  session.presentation.target?.formatted.replacingOccurrences(of: ",", with: "") == arguments[9] else {
                throw Failure("Foreground jump failed after optional read interruption")
            }
            let ready = milliseconds()
            return ["jump_issued_uptime_ms": issued, "jump_ready_ms": ready - issued]
        }
        session.editInterval(arguments[1])
        await session.submitInterval()?.value
        let jumpResult = try await jump.value
        try await settle(trace)
        let events = await trace.snapshot()
        guard let firstOptional = events.first(where: { $0.kind == "optional" }) else {
            throw Failure("No optional reading was observed")
        }
        let probe = AdjacentPrefetchProbe.snapshot()
        guard probe.decodedRecords > 0 else { throw Failure("Native probe never saw a decoded record") }
        var result: [String: Any] = [
            "schema_version": 1, "mode": arguments[8], "bam": arguments[0], "interval": arguments[1],
            "jump_interval": arguments[9], "chunk_bases": Int64(arguments[3])!,
            "first_optional_interval": firstOptional.interval,
            "first_optional_outcome": firstOptional.outcome ?? "unfinished",
            "first_optional_returned_records": firstOptional.records ?? 0,
            "first_optional_total_wall_ms": firstOptional.finishedMilliseconds! - firstOptional.startedMilliseconds,
            "native_decoded_records_before_stop": probe.decodedRecords,
            "first_native_record_uptime_ms": probe.firstRecordMilliseconds,
            "last_native_record_uptime_ms": probe.lastRecordMilliseconds,
            "optional_close_uptime_ms": probe.optionalClosedMilliseconds,
            "first_foreground_record_uptime_ms": probe.foregroundFirstRecordMilliseconds,
            "queries": try JSONSerialization.jsonObject(with: JSONEncoder().encode(events)),
            "measurement_scope": "Production ViewerSession and real reader without a native window/controller; native first-ready/raster is measured separately. Instrumented source snapshot fires one AsyncStream signal after the first successful native optional-record decode. A waiting main-actor task immediately submits foreground navigation; no artificial read/delivery gate or task sleep delays the optional reader. Every decoded optional record updates a locked probe counter, so timings include observer overhead. Native iterator cancellation is still limited by one current blocking HTSlib call/record."
        ]
        for (key, value) in jumpResult { result[key] = value }
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: arguments[7]))
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
        AdjacentPrefetchProbe.disarm()
        signal.continuation.finish()
        if interrupts && firstOptional.outcome != "canceled" {
            throw Failure("Foreground jump did not interrupt active optional reading: \(firstOptional.outcome ?? "unfinished")")
        }
        if interrupts && (probe.optionalClosedMilliseconds <= 0 || probe.foregroundFirstRecordMilliseconds <= 0
            || probe.optionalClosedMilliseconds > probe.foregroundFirstRecordMilliseconds) {
            throw Failure("Native optional iterator closure did not precede foreground decoding")
        }
        if !interrupts && firstOptional.outcome != "complete" {
            throw Failure("Uninterrupted optional control did not finish")
        }
    }
    #endif
}
