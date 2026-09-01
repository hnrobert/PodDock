// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DNSPodKit",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "DNSPodKit", targets: ["DNSPodKit"]),
    .library(name: "PodDockMCP", targets: ["PodDockMCP"]),
    .executable(name: "poddock-mcp", targets: ["PodDockMCPCli"]),
    .executable(name: "poddock-capture", targets: ["PodDockCapture"]),
  ],
  dependencies: [
    // Official MCP Swift SDK, pre-1.0 with a moving API → pin exact; upgrades only touch the PodDockMCP layer
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", exact: "0.12.1"),
    .package(url: "https://github.com/hummingbird-project/hummingbird", exact: "2.26.0"),
    .package(
      url: "https://github.com/swift-server/swift-service-lifecycle", exact: "2.12.0"),
  ],
  targets: [
    .target(name: "DNSPodKit"),
    .target(
      name: "PodDockMCP",
      dependencies: [
        .target(name: "DNSPodKit"),
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
      ]
    ),
    .executableTarget(name: "PodDockMCPCli", dependencies: [.target(name: "PodDockMCP")]),
    .executableTarget(name: "PodDockCapture", dependencies: [.target(name: "DNSPodKit")]),
    .testTarget(name: "DNSPodKitTests", dependencies: [.target(name: "DNSPodKit")]),
  ]
)
