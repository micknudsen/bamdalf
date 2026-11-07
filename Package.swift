// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bamdalf",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Bamdalf", targets: ["Bamdalf"])],
    targets: [
        .target(name: "BamdalfKit"),
        .executableTarget(name: "Bamdalf", dependencies: ["BamdalfKit"]),
        .testTarget(name: "BamdalfKitTests", dependencies: ["BamdalfKit"]),
    ]
)
