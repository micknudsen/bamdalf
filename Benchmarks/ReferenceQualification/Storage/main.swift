import AppKit
import BamdalfKit
import Foundation

struct QualificationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct ReferenceStorageQualification {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3 else {
            FileHandle.standardError.write(Data("usage: create BUNDLE FASTA | probe BUNDLE ORACLE_DIRECTORY\n".utf8))
            exit(EXIT_FAILURE)
        }
        let bundle = URL(fileURLWithPath: args[1])
        let input = URL(fileURLWithPath: args[2])
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                switch args[0] {
                case "create": try await create(bundle, from: input)
                case "probe": try await probe(bundle, oracle: input)
                default: throw QualificationError("Unknown storage action")
                }
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("ReferenceStorageQualification: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        app.run()
    }

    private static func report(_ fields: [String: Any]) throws {
        let json = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data([10]))
    }

    @MainActor
    private static func create(_ output: URL, from source: URL) async throws {
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        guard let window = controller.window, session.presentation.bamURL == nil,
              session.selectedReference == nil, !FileManager.default.fileExists(atPath: output.path) else {
            throw QualificationError("Creation needs an empty viewer and a fresh destination")
        }
        let destination = try ReferenceSaveDestination(confirmedURL: output)
        let start = DispatchTime.now().uptimeNanoseconds
        controller.createReference(nil)
        guard let task = controller.referenceCreation.saveReference(from: source, name: source.deletingPathExtension().lastPathComponent, to: destination),
              controller.referenceCreation.window?.isVisible == true, window.attachedSheet == nil else {
            throw QualificationError("The independent native creation window did not open")
        }
        await task.value
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        guard controller.referenceCreation.window == nil, window.attachedSheet == nil, session.presentation.bamURL == nil,
              session.selectedReference == nil, FileManager.default.fileExists(atPath: output.path) else {
            throw QualificationError("Native Save failed to publish quietly without selecting the result")
        }
        try report(["creation_ns": elapsed])
    }

    private static func probe(_ file: URL, oracle: URL) async throws {
        let dictionary = try Data(contentsOf: oracle.appendingPathComponent("dictionary.tsv"))
        let route = try String(contentsOf: oracle.appendingPathComponent("route.tsv"), encoding: .utf8)
        var openTimes: [UInt64] = []
        for row in route.split(separator: "\n") {
            let fields = row.split(separator: "\t")
            guard fields.count == 4, let start = Int64(fields[1]), let end = Int64(fields[2]) else {
                throw QualificationError("Malformed oracle row")
            }
            let interval = GenomicInterval(reference: String(fields[0]), start: start, end: end)
            let expected = Data(fields[3].utf8)
            let began = DispatchTime.now().uptimeNanoseconds
            let bundle = try ReferenceBundle(opening: file)
            openTimes.append(DispatchTime.now().uptimeNanoseconds - began)
            let observed = bundle.contigs.map { "\($0.name)\t\($0.length)\t\($0.m5)\n" }.joined()
            guard Data(observed.utf8) == dictionary else {
                throw QualificationError("Contig dictionary differs from publisher metadata")
            }
            let first = try await bundle.read(interval)
            let repeated = try await bundle.read(interval)
            guard first == expected, repeated == expected else {
                throw QualificationError("Incorrect sequence at \(interval)")
            }
        }
        guard openTimes.count == 102 else { throw QualificationError("Incomplete open route") }
        try report(["validated_open_ns": openTimes])
    }
}
