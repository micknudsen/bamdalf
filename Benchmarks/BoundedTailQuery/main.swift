import BamdalfKit
import Darwin
import Foundation

/// One expanded production-reader query per process. No native drawing or cache.
@main
struct BoundedTailQuery {
    struct Failure: Error { let message: String }

    @MainActor
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 5, let start = Int64(args[2]), let end = Int64(args[3]),
                  let margin = Int64(args[4]), start > 0, end >= start, margin >= 0 else {
                throw Failure(message: "usage: BoundedTailQuery BAM REFERENCE START END MARGIN")
            }
            let url = URL(fileURLWithPath: args[0]).standardizedFileURL
            let file = try await BAMFile.open(url, indexURL: url.appendingPathExtension("bai"))
            guard let reference = file.references.first(where: { $0.name == args[1] }), end <= reference.length else {
                throw Failure(message: "Target exceeds the reference")
            }
            let requiredStart = start - min(margin, start - 1)
            let requiredEnd = end + min(margin, reference.length - end)
            // Reuse the application's validated interval entry; suppress display so
            // this setup cannot perform a regional query. The injected file shares
            // the same production reader/header/index, without a second opening.
            let session = ViewerSession(loadBAM: { _, _ in file }, alignmentVisibilityLimit: 1)
            await session.openBAM(url)
            session.editInterval("\(args[1]):\(requiredStart)-\(requiredEnd)")
            await session.submitInterval()?.value
            guard session.presentation.isAlignmentSuppressed, let required = session.presentation.target else {
                throw Failure(message: "Required interval validation failed")
            }
            let before = DispatchTime.now().uptimeNanoseconds
            let records = try await file.alignments(in: required)
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - before) / 1_000_000
            let visible = records.filter { $0.drawnStart <= end && $0.drawnEnd >= start }
            let tails = visible.filter { $0.referenceStart > end || $0.referenceEnd < start }
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let result: [String: Any] = [
                "schema_version": 1, "bam": url.path, "reference": args[1],
                "start": start, "end": end, "margin": margin,
                "required_start": requiredStart, "required_end": requiredEnd,
                "required_bases": requiredEnd - requiredStart + 1,
                "query_wall_ms": milliseconds, "query_records": records.count,
                "visible_records": visible.count, "tail_only_records": tails.count,
                "process_peak_rss_bytes": usage.ru_maxrss,
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("BoundedTailQuery: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
