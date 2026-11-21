import AppKit
import BamdalfKit
import Darwin
import Foundation

/// Focused native qualification: production import and viewer in the same process.
@main
struct ReferenceConcurrentQualification {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    actor Queries {
        private var count = 0
        func begin() { count += 1 }
        func value() -> Int { count }
    }

    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run(Array(CommandLine.arguments.dropFirst()))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("ReferenceConcurrentQualification: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        NSApplication.shared.run()
    }

    static func seconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    static func write(_ fields: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: file)
    }

    static func memory(elapsed: Double) throws -> [String: Any] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var usage = rusage()
        guard result == KERN_SUCCESS, getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw Failure("Cannot read process memory")
        }
        return ["elapsed_seconds": elapsed, "resident_bytes": info.resident_size,
                "physical_footprint_bytes": info.phys_footprint,
                "process_peak_resident_bytes": UInt64(usage.ru_maxrss)]
    }

    @MainActor
    static func field(_ label: String, in window: NSWindow) throws -> NSTextField {
        guard let result = window.contentView?.subviews.compactMap({ $0 as? NSTextField })
            .first(where: { $0.accessibilityLabel() == label }) else { throw Failure("Missing \(label)") }
        return result
    }

    @MainActor
    static func edit(_ field: NSTextField, to value: String, in window: NSWindow, submit: Bool = false) throws {
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { throw Failure("No native field editor") }
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        if submit { editor.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
    }

    @MainActor
    static func click(_ label: String, in window: NSWindow) throws {
        guard let button = window.contentView?.subviews.compactMap({ $0 as? NSButton }).first(where: {
            $0.accessibilityLabel() == label || $0.title == label
        }), button.isEnabled, let action = button.action,
              button.sendAction(action, to: button.target) else { throw Failure("Unavailable native action \(label)") }
    }

    @MainActor
    static func ready(_ session: ViewerSession) async throws {
        let deadline = seconds() + 30
        while session.presentation.isLoading || session.presentation.isOpening {
            guard seconds() < deadline else { throw Failure("Navigation observation exceeded 30s timeout") }
            try await Task.sleep(for: .milliseconds(1))
        }
        let state = session.presentation
        guard state.intervalError == nil, state.regionalError == nil, state.openError == nil,
              state.indexChoice == nil, state.target != nil else {
            throw Failure(state.intervalError ?? state.regionalError?.message ?? state.openError?.message ?? "No target or unresolved index choice")
        }
    }

    @MainActor
    static func run(_ args: [String]) async throws {
        guard args.count == 5 || (args.count == 6 && args[5] == "baseline") else {
            throw Failure("usage: FASTA NEW_BUNDLE EXISTING_V2_BUNDLE BAM_OR_DASH RESULT_DIRECTORY [baseline]")
        }
        let baseline = args.count == 6
        let source = URL(fileURLWithPath: args[0]).standardizedFileURL
        let output = URL(fileURLWithPath: args[1]).standardizedFileURL
        let reference = URL(fileURLWithPath: args[2]).standardizedFileURL
        let bam = args[3] == "-" ? nil : URL(fileURLWithPath: args[3]).standardizedFileURL
        let results = URL(fileURLWithPath: args[4]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: results.path),
              baseline || !FileManager.default.fileExists(atPath: output.path) else {
            throw Failure("Use fresh result directory and output file")
        }
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        var samples: [[String: Any]] = []
        var memorySamples: [[String: Any]] = []
        var phase = "viewer setup"
        var failedAction: [String: Any] = [:]
        var measurementStarted: Double?
        do {
            let queries = Queries()
            let session = ViewerSession(loadRegion: { file, interval in
                await queries.begin()
                return try await file.alignments(in: interval)
            }, samplingSeed: { 42 })
            var panelFailure: Error?
            var saveApproved = false
            let controller = ViewerWindowController(session: session) { panel, owner, complete in
                do {
                    guard !(panel is NSOpenPanel), owner.title == "Create Reference",
                          panel.allowedContentTypes.map(\.preferredFilenameExtension) == ["bref"],
                          let approval = panel.delegate as? ReferenceSaveApproval else {
                        throw Failure("Expected production native Save configuration")
                    }
                    try approval.panel(panel, validate: output)
                    saveApproved = true
                    complete(output)
                } catch { panelFailure = error; complete(nil) }
            }
            guard let window = controller.window, let content = window.contentView,
                  let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first,
                  let renderer = scroll.documentView,
                  let ruler = content.subviews.first(where: { $0.accessibilityLabel() == "Genomic ruler" }),
                  let referenceRow = content.subviews.first(where: { $0.accessibilityLabel() == "Reference sequence" }) else {
                throw Failure("Missing native viewer")
            }
            window.appearance = NSAppearance(named: .aqua)
            window.setContentSize(NSSize(width: 1100, height: 720))
            controller.showWindow(nil)
            await session.openReference(reference)
            if let bam { await controller.openBAM(at: bam) }
            try edit(try field("Genomic interval", in: window), to: "chr20:10,025,001-10,025,100", in: window, submit: true)
            try await ready(session)
            guard session.presentation.referenceURL == reference, session.presentation.bamURL == bam else {
                throw Failure("Sources did not open")
            }
            content.layoutSubtreeIfNeeded()
            let alignmentSurface = try Surface(size: scroll.contentSize, scale: window.backingScaleFactor)
            let rulerSurface = try Surface(size: ruler.bounds.size, scale: window.backingScaleFactor)
            let referenceSurface = try Surface(size: referenceRow.bounds.size, scale: window.backingScaleFactor)
            func draw() {
                content.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                alignmentSurface.draw(renderer, window: window)
                rulerSurface.draw(ruler, window: window, rect: ruler.bounds)
                referenceSurface.draw(referenceRow, window: window, rect: referenceRow.bounds)
            }
            draw()
            phase = "creation form"
            let chosenName = "Concurrent GRCh38 qualification"
            var form: NSWindow?
            var indicator: NSProgressIndicator?
            var closedAt: Double?
            var closeObserver: NSObjectProtocol?
            if !baseline {
                controller.createReference(nil)
                guard let creationWindow = controller.referenceCreation.window else { throw Failure("No creation form") }
                form = creationWindow
                try edit(try field("FASTA", in: creationWindow), to: source.path, in: creationWindow)
                try edit(try field("Bundle name", in: creationWindow), to: chosenName, in: creationWindow)
                indicator = creationWindow.contentView?.subviews.compactMap { $0 as? NSProgressIndicator }.first
                guard indicator != nil else { throw Failure("No import progress control") }
                closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                    object: creationWindow, queue: .main) { _ in
                        MainActor.assumeIsolated { closedAt = seconds() }
                    }
            }
            defer {
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                window.close()
            }
            try write(["mode": baseline ? "baseline" : "concurrent", "fasta": source.path,
                       "reference": reference.path, "bam": bam?.path ?? "", "output": output.path,
                       "width_points": content.bounds.width, "height_points": content.bounds.height,
                       "backing_scale": window.backingScaleFactor, "cadence_pause_ms": 100,
                       "timing_boundary": "native input handler, required readiness, synchronous native CPU raster; excludes OS input delivery and display presentation"],
                      to: results.appendingPathComponent("environment.json"))
            phase = "start import"
            let started = seconds()
            measurementStarted = started
            if let form { try click("Create bundle", in: form) }
            if let panelFailure { throw panelFailure }
            if !baseline {
                guard saveApproved else { throw Failure("Save was not approved") }
                let deadline = seconds() + 10
                while indicator?.observedProgress == nil && closedAt == nil {
                    guard seconds() < deadline else { throw Failure("Import did not start") }
                    try await Task.sleep(for: .milliseconds(1))
                }
                guard closedAt == nil, window.attachedSheet == nil,
                      indicator?.observedProgress != nil else { throw Failure("Import never overlapped browsing") }
            }
            window.makeKeyAndOrderFront(nil)
            memorySamples = [try memory(elapsed: 0)]
            let memoryTask = Task { @MainActor in
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(250))
                    memorySamples.append(try memory(elapsed: seconds() - started))
                }
            }
            defer { memoryTask.cancel() }
            let steps: [(String, String?)] = [
                ("type-A", "chr20:10,025,001-10,025,100"), ("Pan right", nil), ("Pan left", nil), ("Zoom out", nil), ("Zoom in", nil),
                ("type-B", "chr20:20,050,001-20,050,100"), ("Pan right", nil), ("Pan left", nil), ("Zoom out", nil), ("Zoom in", nil),
            ]
            // Independently worked expected coordinates for the fixed route:
            // 100-base views pan 50 bases; centered zoom-out doubles to 200.
            let expected: [(Int64, Int64)] = [
                (10_025_001, 10_025_100), (10_025_051, 10_025_150), (10_025_001, 10_025_100),
                (10_024_951, 10_025_150), (10_025_001, 10_025_100),
                (20_050_001, 20_050_100), (20_050_051, 20_050_150), (20_050_001, 20_050_100),
                (20_049_951, 20_050_150), (20_050_001, 20_050_100),
            ]
            var index = 0
            while (baseline ? seconds() - started < 20 : closedAt == nil) || index % steps.count != 0 {
                phase = "import and navigation"
                let coordinates = expected[index % expected.count]
                let expectedTarget = GenomicInterval(reference: "chr20", start: coordinates.0, end: coordinates.1)
                failedAction = ["index": index, "action": steps[index % steps.count].0,
                                "expected_interval": expectedTarget.formatted,
                                "before_interval": session.presentation.target?.formatted ?? ""]
                guard seconds() - started < 180 else { throw Failure("Creation observation exceeded 180s timeout") }
                if let form, let failure = try? field("Creation error", in: form), !failure.stringValue.isEmpty {
                    throw Failure(failure.stringValue)
                }
                let step = steps[index % steps.count]
                let beforeQueries = await queries.value()
                let progressBefore = indicator?.observedProgress?.completedUnitCount ?? 0
                let beforeInterval = session.presentation.target?.formatted ?? ""
                failedAction["progress_bytes_before"] = progressBefore
                let start = seconds()
                let runningBefore = !baseline && closedAt == nil
                if let interval = step.1 {
                    try edit(try field("Genomic interval", in: window), to: interval, in: window, submit: true)
                } else { try click(step.0, in: window) }
                try await ready(session)
                draw()
                let ended = seconds()
                let queryCount = await queries.value() - beforeQueries
                failedAction["started_seconds"] = start - started
                failedAction["ended_seconds"] = ended - started
                failedAction["elapsed_ms"] = (ended - start) * 1000
                failedAction["observed_interval"] = session.presentation.target?.formatted ?? ""
                failedAction["required_queries"] = queryCount
                guard session.presentation.target == expectedTarget,
                      let bases = session.presentation.referenceBases,
                      bases.interval.reference == "chr20", bases.interval.start <= coordinates.0,
                      bases.interval.end >= coordinates.1,
                      bases.bases.count == Int(bases.interval.end - bases.interval.start + 1),
                      bam == nil || !session.presentation.alignments.isEmpty else {
                    throw Failure("Native action did not produce its expected interval and loaded reference/alignment data")
                }
                guard session.presentation.referenceURL == reference, session.presentation.bamURL == bam,
                      window.attachedSheet == nil else { throw Failure("Import disturbed viewer sources or blocked navigation") }
                samples.append(["index": index, "cycle": index / steps.count, "action": step.0,
                    "started_seconds": start - started, "ended_seconds": ended - started,
                    "elapsed_ms": (ended - start) * 1000, "required_queries": queryCount,
                    "target_ms": queryCount == 0 ? 100 : 500,
                    "before_interval": beforeInterval, "interval": session.presentation.target?.formatted ?? "",
                    "reference_bases": bases.bases.count, "alignment_count": session.presentation.alignments.count,
                    "progress_bytes_before": progressBefore,
                    "progress_bytes_after": indicator?.observedProgress?.completedUnitCount ?? progressBefore,
                    "import_running_before": runningBefore, "import_running_after": !baseline && closedAt == nil])
                index += 1
                try await Task.sleep(for: .milliseconds(100))
            }
            phase = "final memory sample"
            failedAction = [:]
            memoryTask.cancel()
            do { try await memoryTask.value } catch is CancellationError { }
            memorySamples.append(try memory(elapsed: seconds() - started))
            let finalTarget = session.presentation.target?.formatted ?? ""
            phase = "completed bundle validation"
            if !baseline {
                guard controller.referenceCreation.window == nil, let form, !form.isVisible,
                      !samples.isEmpty, samples.contains(where: { ($0["progress_bytes_after"] as? Int64 ?? 0) > 0 }) else {
                    throw Failure("Creation did not quietly finish during measured navigation")
                }
                let bundle = try ReferenceBundle(opening: output)
                guard bundle.name == chosenName, bundle.contigs.count == 2580,
                      bundle.contigs.reduce(Int64(0), { $0 + $1.length }) == 3_105_715_063 else {
                    throw Failure("Created bundle name/dictionary does not match representative GRCh38")
                }
            }
            phase = "capture writing"
            try alignmentSurface.writePNG(results.appendingPathComponent("final-alignments.png"))
            try rulerSurface.writePNG(results.appendingPathComponent("final-ruler.png"))
            try referenceSurface.writePNG(results.appendingPathComponent("final-reference.png"))
            phase = "results writing"
            try write(["completed": true, "mode": baseline ? "baseline" : "concurrent",
                "creation_seconds": closedAt.map { $0 - started } ?? NSNull(),
                "elapsed_seconds": seconds() - started, "navigation_count": samples.count,
                "final_interval": finalTarget, "samples": samples, "memory": memorySamples],
                to: results.appendingPathComponent("results.json"))
            FileHandle.standardOutput.write(Data("COMPLETED native concurrent qualification: \(samples.count) navigation observations\n".utf8))
        } catch {
            // Keep completed observations and the failing step even when import,
            // navigation, validation, or capture fails. Never emit completion.
            let failure: [String: Any] = ["completed": false,
                "mode": baseline ? "baseline" : "concurrent", "error": String(describing: error),
                "phase": phase, "failed_action": failedAction,
                "elapsed_seconds": measurementStarted.map { seconds() - $0 } ?? NSNull(),
                "navigation_count": samples.count, "samples": samples, "memory": memorySamples]
            do { try write(failure, to: results.appendingPathComponent("results.json")) }
            catch {
                FileHandle.standardError.write(Data("Could not preserve failure artifact: \(error)\n".utf8))
            }
            throw error
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
}
