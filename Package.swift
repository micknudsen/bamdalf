// swift-tools-version: 6.0
import PackageDescription
import Foundation

let htslib = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".build/htslib").path

let package = Package(
    name: "Bamdalf",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Bamdalf", targets: ["Bamdalf"])],
    targets: [
        .target(
            name: "CBAM",
            cSettings: [.unsafeFlags(["-isystem", "\(htslib)/include"])],
            linkerSettings: [.unsafeFlags(["\(htslib)/lib/libhts.a"]), .linkedLibrary("z")]
        ),
        .target(name: "BamdalfKit", dependencies: ["CBAM"]),
        .executableTarget(name: "Bamdalf", dependencies: ["BamdalfKit"]),
        .testTarget(name: "BamdalfKitTests", dependencies: ["BamdalfKit"], resources: [.copy("Fixtures")]),
    ]
)
