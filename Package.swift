// swift-tools-version: 6.0
import PackageDescription
import Foundation

let htslib = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".build/htslib").path

let package = Package(
    name: "bamdalf",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "bamdalf", targets: ["Bamdalf"])],
    targets: [
        .target(
            name: "CBAM",
            cSettings: [.unsafeFlags(["-isystem", "\(htslib)/include"])],
            linkerSettings: [.unsafeFlags(["\(htslib)/lib/libhts.a"]), .linkedLibrary("z")]
        ),
        .target(name: "BamdalfKit", dependencies: ["CBAM"]),
        .executableTarget(name: "Bamdalf", dependencies: ["BamdalfKit"]),
        .executableTarget(name: "VisibilityBaseline", dependencies: ["BamdalfKit"], path: "Benchmarks",
                          exclude: ["Qualification.swift", "run-qualification.sh", "qualification-protocol-v1.json", "qualification-protocol-v2.json", "summarize-qualification.py", "run-visibility-baseline.sh", "run-sampling-baseline.sh", "README.md", "Data", "BoundedTailQuery"], sources: ["VisibilityBaseline.swift"]),
        .executableTarget(name: "Qualification", dependencies: ["BamdalfKit"], path: "Benchmarks",
                          exclude: ["VisibilityBaseline.swift", "run-qualification.sh", "qualification-protocol-v1.json", "qualification-protocol-v2.json", "summarize-qualification.py", "run-visibility-baseline.sh", "run-sampling-baseline.sh", "README.md", "Data", "BoundedTailQuery"], sources: ["Qualification.swift"]),
        .executableTarget(name: "BoundedTailQuery", dependencies: ["BamdalfKit"], path: "Benchmarks/BoundedTailQuery",
                          exclude: ["run.py", "native.py"], sources: ["main.swift"]),
        .testTarget(name: "BamdalfKitTests", dependencies: ["BamdalfKit"], resources: [.copy("Fixtures")]),
    ]
)
