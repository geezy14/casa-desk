// swift-tools-version: 6.0
import PackageDescription

// Casa Desk — a local, READ-ONLY Apple toolkit for assistants (2026-10-03).
// The Info.plist is linked INTO the binary (-sectcreate) so macOS privacy (TCC) can show a usage reason and
// remember the grant for this tool. Without it, EventKit/Contacts requests from a bare CLI are refused.
let package = Package(
    name: "casa-desk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "casa-desk", targets: ["CasaDesk"])],
    targets: [
        .target(name: "CasaDeskCore"),
        .executableTarget(
            name: "CasaDesk",
            dependencies: ["CasaDeskCore"],
            // Swift 5 mode: a one-shot CLI with no shared state across tasks; strict-concurrency checks add nothing here.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "Support/Info.plist"]),
            ]
        ),
        .testTarget(name: "CasaDeskCoreTests", dependencies: ["CasaDeskCore"]),
    ]
)
