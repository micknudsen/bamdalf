import AppKit
import BamdalfKit
import CryptoKit
import Darwin
import Foundation

/// Drives the real public session and native controls. No alternative sampler,
/// query cache, layout, or renderer is implemented in this measurement executable.
@main
struct Qualification {
    struct ProtocolFile: Decodable {
        let schema_version: Int
        let cases: [Case]
    }

    struct Case: Decodable {
        let id: String
        let bam: String
        let repetitions: Int
        let fresh_session: Bool
        let setup: [Step]
        let steps: [Step]
        let finish: [Step]?
        let duration_seconds: Double?
        let pause_ms: Double?
    }

    struct Step: Decodable {
        let id: String
        let action: String
        let interval: String?
        let fraction: Double?
        let delta: Int32?
        let measure: Bool?
        let expected_query: String?
        let expected_interval: String?
        let expected_sampled: Bool?
        let expected_suppressed: Bool?
        let expected_records: Int?
        let expected_queried_records: Int?
        let expected_continuity: Bool?
        let expected_selection_of: String?
        let capture: Bool?
        let target_ms: Double?
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    struct QuerySnapshot: Sendable {
        var calls = 0
        var records = 0
        var wallMilliseconds = 0.0
    }

    actor Queries {
        private var work = QuerySnapshot()
        func record(_ count: Int, _ milliseconds: Double) {
            work.calls += 1
            work.records += count
            work.wallMilliseconds += milliseconds
        }
        func snapshot() -> QuerySnapshot { work }
    }

    struct Memory: Codable, Sendable {
        let elapsed_seconds: Double
        let resident_bytes: UInt64
        let physical_footprint_bytes: UInt64
        let process_peak_resident_bytes: UInt64
    }

    actor MemoryTrace {
        private let handle: FileHandle
        private let start: Double
        private(set) var count = 0
        private(set) var maximumResident: UInt64 = 0
        private(set) var maximumFootprint: UInt64 = 0
        init(url: URL) throws {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw Failure("Cannot create memory trace")
            }
            handle = try FileHandle(forWritingTo: url)
            start = wallSeconds()
        }
        func sample() throws {
            let sample = try memory(elapsed: wallSeconds() - start)
            var data = try JSONEncoder().encode(sample)
            data.append(0x0A)
            try handle.write(contentsOf: data)
            maximumResident = max(maximumResident, sample.resident_bytes)
            maximumFootprint = max(maximumFootprint, sample.physical_footprint_bytes)
            count += 1
        }
        func close() throws { try handle.synchronize(); try handle.close() }
    }

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run(Array(CommandLine.arguments.dropFirst()))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Qualification: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        application.run()
    }

    private static func wallSeconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func memory(elapsed: Double) throws -> Memory {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw Failure("task_info failed: \(result)") }
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw Failure("getrusage failed") }
        return Memory(elapsed_seconds: elapsed, resident_bytes: info.resident_size,
                      physical_footprint_bytes: info.phys_footprint,
                      process_peak_resident_bytes: UInt64(usage.ru_maxrss))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }

    @MainActor
    final class Workspace {
        let queries = Queries()
        let session: ViewerSession
        let controller: ViewerWindowController
        let window: NSWindow
        let content: NSView
        let scroll: NSScrollView
        let renderer: NSView
        let ruler: NSView
        let field: NSTextField
        let rendererSurface: Surface
        let rulerSurface: Surface
        var selections: [String: [UInt64]] = [:]

        init() throws {
            let queryWork = queries
            session = ViewerSession(loadRegion: { file, target in
                let start = wallSeconds()
                let records = try await file.alignments(in: target)
                await queryWork.record(records.count, (wallSeconds() - start) * 1000)
                return records
            }, samplingSeed: { 42 })
            controller = ViewerWindowController(session: session)
            guard let window = controller.window, let content = window.contentView,
                  let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first,
                  let renderer = scroll.documentView,
                  let ruler = content.subviews.first(where: { $0.accessibilityLabel() == "Genomic ruler" }),
                  let field = content.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) else {
                throw Failure("Missing native workspace/control")
            }
            self.window = window; self.content = content; self.scroll = scroll
            self.renderer = renderer; self.ruler = ruler; self.field = field
            window.appearance = NSAppearance(named: .aqua)
            window.setContentSize(NSSize(width: 1100, height: 720))
            window.makeKeyAndOrderFront(nil)
            content.layoutSubtreeIfNeeded()
            rendererSurface = try Surface(size: scroll.contentSize, scale: window.backingScaleFactor)
            rulerSurface = try Surface(size: ruler.bounds.size, scale: window.backingScaleFactor)
        }

        func open(_ path: String) async throws {
            await controller.openBAM(at: URL(fileURLWithPath: path).standardizedFileURL)
            guard session.presentation.bamURL != nil, session.presentation.indexChoice == nil,
                  session.presentation.openError == nil else {
                throw Failure(session.presentation.openError?.message ?? "Opening needs exactly one sibling index")
            }
            try await Task.sleep(for: .milliseconds(50))
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        func close() {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }

        func mouse(_ type: NSEvent.EventType, fraction: Double, clicks: Int = 1,
                   modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type,
                location: renderer.convert(NSPoint(x: renderer.bounds.width * fraction,
                                                   y: renderer.visibleRect.minY + 8), to: nil),
                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: clicks, pressure: 1) else { throw Failure("Cannot make pointer event") }
            return event
        }

        func action(_ step: Step) throws {
            switch step.action {
            case "type":
                guard let text = step.interval else { throw Failure("type needs interval") }
                window.makeFirstResponder(field)
                guard let editor = field.currentEditor() as? NSTextView else {
                    throw Failure("Native interval field editor unavailable")
                }
                editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                // Keep keyboard focus out of the renderer, matching real typing.
            case "pan_left", "pan_right", "zoom_in", "zoom_out":
                let labels = ["pan_left": "Pan left", "pan_right": "Pan right", "zoom_in": "Zoom in", "zoom_out": "Zoom out"]
                guard let button = content.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.accessibilityLabel() == labels[step.action] }), button.isEnabled else {
                    throw Failure("Native \(step.action) control unavailable")
                }
                // Dispatch the actual control's configured action. performClick
                // also waits through a synthetic highlight animation; that is
                // not the user-input handler's cost in a real mouse-up action.
                guard let action = button.action, button.sendAction(action, to: button.target) else {
                    throw Failure("Native \(step.action) action was not dispatched")
                }
            case "mouse_down":
                renderer.mouseDown(with: try mouse(.leftMouseDown, fraction: step.fraction ?? 0.5))
            case "mouse_drag":
                renderer.mouseDragged(with: try mouse(.leftMouseDragged, fraction: step.fraction ?? 0.5))
            case "mouse_up":
                renderer.mouseUp(with: try mouse(.leftMouseUp, fraction: step.fraction ?? 0.5))
            case "double_click", "option_click":
                let count = step.action == "double_click" ? 2 : 1
                let modifiers: NSEvent.ModifierFlags = step.action == "option_click" ? .option : []
                renderer.mouseDown(with: try mouse(.leftMouseDown, fraction: step.fraction ?? 0.5, clicks: count, modifiers: modifiers))
                renderer.mouseUp(with: try mouse(.leftMouseUp, fraction: step.fraction ?? 0.5, clicks: count, modifiers: modifiers))
            case "scroll":
                guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                          wheel1: step.delta ?? -36, wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: wheel) else { throw Failure("Cannot make wheel event") }
                renderer.scrollWheel(with: event)
            default: throw Failure("Unknown action \(step.action)")
            }
        }

        func ready() async throws {
            let deadline = wallSeconds() + 30
            while session.presentation.isLoading {
                guard wallSeconds() < deadline else { throw Failure("Regional load exceeded 30 second observation timeout") }
                try await Task.sleep(for: .milliseconds(1))
            }
            guard session.presentation.intervalError == nil,
                  session.presentation.regionalError == nil,
                  session.presentation.target != nil else {
                throw Failure(session.presentation.intervalError ?? session.presentation.regionalError?.message ?? "No target")
            }
        }

        func draw() {
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            rendererSurface.draw(renderer, window: window)
            rulerSurface.draw(ruler, window: window, rect: ruler.bounds)
        }

        func capture(_ prefix: URL) throws {
            try rendererSurface.writePNG(prefix.appendingPathExtension("alignments.png"))
            try rulerSurface.writePNG(prefix.appendingPathExtension("ruler.png"))
            if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try data.write(to: prefix.appendingPathExtension("supplementary-content.png"))
                }
            }
        }
    }

    @MainActor
    final class Surface {
        let bitmap: NSBitmapImageRep
        let context: NSGraphicsContext
        let scale: CGFloat
        init(size: NSSize, scale: CGFloat) throws {
            guard size.width > 0, size.height > 0,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(ceil(size.width * scale)), pixelsHigh: Int(ceil(size.height * scale)),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw Failure("Cannot allocate native drawing surface")
            }
            bitmap.size = size
            self.bitmap = bitmap; self.context = context; self.scale = scale
        }
        func draw(_ view: NSView, window: NSWindow, rect: NSRect? = nil) {
            let visible = rect ?? view.visibleRect
            let cg = context.cgContext
            cg.saveGState()
            cg.scaleBy(x: scale, y: scale)
            if view.isFlipped {
                cg.translateBy(x: 0, y: bitmap.size.height)
                cg.scaleBy(x: 1, y: -1)
            }
            cg.translateBy(x: -visible.minX, y: -visible.minY)
            cg.clip(to: visible)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: view.isFlipped)
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.textBackgroundColor.setFill()
                visible.fill()
                view.draw(visible)
                // Ruler labels are native NSTextField children, not content of
                // the ruler's draw override. Rasterize them through their own
                // native draw methods as part of the same visual update.
                drawChildren(of: view, context: cg)
            }
            cg.flush()
            NSGraphicsContext.restoreGraphicsState()
            cg.restoreGState()
        }
        private func drawChildren(of view: NSView, context: CGContext) {
            for child in view.subviews where !child.isHidden {
                context.saveGState()
                context.translateBy(x: child.frame.minX, y: child.frame.minY)
                if view.isFlipped != child.isFlipped {
                    context.translateBy(x: 0, y: child.frame.height)
                    context.scaleBy(x: 1, y: -1)
                }
                context.clip(to: child.bounds)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: child.isFlipped)
                child.draw(child.bounds)
                drawChildren(of: child, context: context)
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
            }
        }
        func writePNG(_ url: URL) throws {
            // NSBitmapImageRep can cache its first encoded image even while its
            // drawing context continues changing. Snapshot the current context.
            guard let image = context.cgContext.makeImage(),
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw Failure("Cannot encode capture")
            }
            try data.write(to: url)
        }
    }

    @MainActor
    private static func run(_ args: [String]) async throws {
        guard (2...3).contains(args.count) else {
            throw Failure("usage: Qualification PROTOCOL.json NEW_OUTPUT_DIRECTORY [CASE_ID]")
        }
        let protocolURL = URL(fileURLWithPath: args[0]).standardizedFileURL
        let output = URL(fileURLWithPath: args[1]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw Failure("Output already exists; preserve previous evidence")
        }
        let data = try Data(contentsOf: protocolURL)
        let plan = try JSONDecoder().decode(ProtocolFile.self, from: data)
        guard plan.schema_version == 1 else { throw Failure("Unsupported schema") }
        var identifiers = Set<String>()
        for item in plan.cases {
            guard safeName(item.id), identifiers.insert(item.id).inserted,
                  item.repetitions > 0, !item.steps.isEmpty,
                  item.duration_seconds == nil || (!item.fresh_session && item.duration_seconds! > 0),
                  item.pause_ms == nil || item.pause_ms! >= 0 else { throw Failure("Invalid case \(item.id)") }
            for step in item.setup + item.steps + (item.finish ?? []) {
                guard safeName(step.id), step.fraction == nil || step.fraction!.isFinite,
                      step.target_ms == nil || step.target_ms! > 0,
                      step.expected_query == nil || ["zero", "positive"].contains(step.expected_query!) else {
                    throw Failure("Invalid step \(step.id)")
                }
            }
        }
        let cases = plan.cases.filter { args.count == 2 || $0.id == args[2] }
        guard !cases.isEmpty else { throw Failure("No matching cases") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent("protocol.json"))
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let metadata: [String: Any] = [
            "schema_version": 1,
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "protocol_sha256": sha256(data),
            "executable_sha256": sha256(try Data(contentsOf: executable)),
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "window_width_points": 1100, "window_height_points": 720,
            "sampling_seed": 42,
            "scope": "Wall time begins before native input handling (field-editor insertion/Enter, native NSButton action dispatch without performClick synthetic highlighting, direct native pointer/wheel handlers) and includes regional completion, native layout/display requests and synchronous rasterization by the actual alignment/ruler NSViews into reused viewport-sized bitmaps. Excludes OS event-queue delivery, compositor presentation, PNG encoding, validation, and metric output. Polling regional readiness may add up to approximately 1 ms. OS file caches uncontrolled; fresh_session resets only application state. Native content captures may omit layer-backed content; renderer/ruler captures are separate. Memory trace is process task_vm_info resident size and physical footprint every 250 ms; getrusage peak RSS is the process lifetime maximum, bytes on macOS."
        ]
        try writeJSON(metadata, to: output.appendingPathComponent("environment.json"))
        for item in cases {
            try await runCase(item, output: output)
        }
        try writeJSON(["completed": true, "cases": cases.map(\.id), "protocol_sha256": sha256(data)],
                      to: output.appendingPathComponent("completion.json"))
    }

    private static func writeJSON(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    @MainActor
    private static func runCase(_ item: Case, output: URL) async throws {
        let directory = output.appendingPathComponent(item.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let trace = try MemoryTrace(url: directory.appendingPathComponent("memory.jsonl"))
        try await trace.sample()
        let tracing = Task.detached {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { try await trace.sample() }
            }
        }
        let recordsURL = directory.appendingPathComponent("samples.jsonl")
        guard FileManager.default.createFile(atPath: recordsURL.path, contents: nil) else { throw Failure("Cannot create samples") }
        let records = try FileHandle(forWritingTo: recordsURL)
        let started = wallSeconds()
        var workspace: Workspace?
        var iteration = 0
        var sampleCount = 0
        var durationStart: Double?
        let remembered = Set((item.setup + item.steps + (item.finish ?? [])).compactMap(\.expected_selection_of))
        do {
            repeat {
                if workspace == nil {
                    workspace = try Workspace()
                    try await workspace!.open(item.bam)
                    for step in item.setup {
                        try await perform(step, caseID: item.id, iteration: iteration, phase: "setup", workspace: workspace!,
                                          output: directory, records: records, remembered: remembered, elapsedStart: started)
                    }
                    if durationStart == nil { durationStart = wallSeconds() }
                }
                for step in item.steps {
                    try await perform(step, caseID: item.id, iteration: iteration, phase: "steps", workspace: workspace!,
                                      output: directory, records: records, remembered: remembered, elapsedStart: started)
                    sampleCount += 1
                    if let pause = item.pause_ms, pause > 0 {
                        try await Task.sleep(for: .milliseconds(pause))
                    }
                }
                iteration += 1
                if item.fresh_session {
                    for step in item.finish ?? [] {
                        try await perform(step, caseID: item.id, iteration: iteration - 1, phase: "finish", workspace: workspace!,
                                          output: directory, records: records, remembered: remembered, elapsedStart: started)
                    }
                    workspace!.close(); workspace = nil
                }
            } while item.duration_seconds.map { wallSeconds() - durationStart! < $0 } ?? (iteration < item.repetitions)
            if let workspace {
                for step in item.finish ?? [] {
                    try await perform(step, caseID: item.id, iteration: iteration - 1, phase: "finish", workspace: workspace,
                                      output: directory, records: records, remembered: remembered, elapsedStart: started)
                }
                workspace.close()
            }
            tracing.cancel()
            do { try await tracing.value } catch is CancellationError {}
            try await trace.sample()
            try await trace.close()
            try records.synchronize(); try records.close()
            let final = try memory(elapsed: wallSeconds() - started)
            try writeJSON([
                "case": item.id, "completed": true, "iterations": iteration,
                "steps": sampleCount, "elapsed_seconds": final.elapsed_seconds,
                "navigation_elapsed_seconds": wallSeconds() - (durationStart ?? started),
                "sampled_peak_resident_bytes": await trace.maximumResident,
                "sampled_peak_physical_footprint_bytes": await trace.maximumFootprint,
                "process_lifetime_peak_resident_bytes": final.process_peak_resident_bytes,
                "memory_trace_samples": await trace.count,
                "memory_target_bytes": 2_147_483_648,
                "memory_target_met": final.process_peak_resident_bytes < 2_147_483_648
            ], to: directory.appendingPathComponent("completion.json"))
            print("Completed \(item.id): \(iteration) iterations, \(sampleCount) steps")
        } catch {
            workspace?.close()
            tracing.cancel()
            _ = try? await tracing.value
            try? await trace.close()
            try? records.close()
            throw error
        }
    }

    @MainActor
    private static func perform(_ step: Step, caseID: String, iteration: Int, phase: String, workspace: Workspace,
                                output: URL, records: FileHandle, remembered: Set<String>, elapsedStart: Double) async throws {
        let before = workspace.session.presentation
        let queryBefore = await workspace.queries.snapshot()
        let start = wallSeconds()
        try workspace.action(step)
        // A preview deliberately has no pending query; no synthetic submission
        // is made to obtain a task or to force the preview to commit.
        try await workspace.ready()
        workspace.draw()
        let milliseconds = (wallSeconds() - start) * 1000
        let after = workspace.session.presentation
        let queryAfter = await workspace.queries.snapshot()
        let queryCount = queryAfter.calls - queryBefore.calls
        if let expected = step.expected_query {
            guard expected == "zero" ? queryCount == 0 : queryCount > 0 else {
                throw Failure("\(caseID)/\(step.id): expected \(expected) queries, got \(queryCount)")
            }
        }
        if let expected = step.expected_interval {
            guard let target = after.target,
                  target.formatted.replacingOccurrences(of: ",", with: "") == expected.replacingOccurrences(of: ",", with: "") else {
                throw Failure("\(caseID)/\(step.id): target \(after.target?.formatted ?? "nil") differs from \(expected)")
            }
        }
        if let expected = step.expected_sampled, after.isDownsampled != expected {
            throw Failure("\(caseID)/\(step.id): unexpected sampling status")
        }
        if let expected = step.expected_suppressed, after.isAlignmentSuppressed != expected {
            throw Failure("\(caseID)/\(step.id): unexpected wide status")
        }
        if let expected = step.expected_records, after.alignments.count != expected {
            throw Failure("\(caseID)/\(step.id): expected \(expected) retained records, got \(after.alignments.count)")
        }
        if let expected = step.expected_queried_records, queryAfter.records - queryBefore.records != expected {
            throw Failure("\(caseID)/\(step.id): expected \(expected) query records, got \(queryAfter.records - queryBefore.records)")
        }
        var retained = 0
        if step.expected_continuity == true {
            let old = Dictionary(uniqueKeysWithValues: before.alignments.map { ($0.id, $0.row) })
            for alignment in after.alignments {
                if let row = old[alignment.id] {
                    guard row == alignment.row else { throw Failure("\(caseID)/\(step.id): retained row moved") }
                    retained += 1
                }
            }
            guard after.rowCount >= before.rowCount else { throw Failure("\(caseID)/\(step.id): retained row extent shrank") }
        }
        let ids = after.alignments.map(\.id).sorted()
        if let baseline = step.expected_selection_of {
            guard let previous = workspace.selections[baseline], previous == ids else {
                throw Failure("\(caseID)/\(step.id): selection differs from \(baseline)")
            }
        }
        if remembered.contains(step.id) { workspace.selections[step.id] = ids }
        var idBytes = Data()
        for id in ids { var value = id.bigEndian; withUnsafeBytes(of: &value) { idBytes.append(contentsOf: $0) } }
        let usage = try memory(elapsed: wallSeconds() - elapsedStart)
        var row: [String: Any] = [
            "case": caseID, "step": step.id, "phase": phase, "iteration": iteration,
            "action": step.action, "measured": phase == "steps" && step.measure != false,
            "wall_ms": milliseconds, "elapsed_seconds": usage.elapsed_seconds,
            "interval": after.target?.formatted ?? "", "query_calls": queryCount,
            "queried_records": queryAfter.records - queryBefore.records,
            "query_wall_ms": queryAfter.wallMilliseconds - queryBefore.wallMilliseconds,
            "alignments": after.alignments.count, "rows": after.rowCount,
            "is_downsampled": after.isDownsampled, "is_suppressed": after.isAlignmentSuppressed,
            "vertical_offset_points": after.verticalOffset,
            "previous_vertical_offset_points": before.verticalOffset,
            "retained_rows_checked": retained, "selection_sha256": sha256(idBytes),
            "viewport_width_points": workspace.renderer.visibleRect.width,
            "viewport_height_points": workspace.renderer.visibleRect.height,
            "ruler_labels": workspace.ruler.subviews.compactMap { ($0 as? NSTextField)?.stringValue },
            "backing_scale": workspace.window.backingScaleFactor,
            "resident_bytes": usage.resident_bytes,
            "physical_footprint_bytes": usage.physical_footprint_bytes,
            "process_peak_resident_bytes": usage.process_peak_resident_bytes
        ]
        if let target = step.target_ms { row["target_ms"] = target; row["met_target"] = milliseconds <= target }
        if step.capture == true && iteration == 0 {
            let prefix = output.appendingPathComponent("\(phase)-\(step.id)")
            try workspace.capture(prefix)
            row["capture_prefix"] = prefix.lastPathComponent
        }
        var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        data.append(0x0A)
        try records.write(contentsOf: data)
    }
}
