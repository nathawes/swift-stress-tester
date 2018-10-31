// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "SourceKitStressTester",
  products: [
    .executable(name: "sk-stress-test", targets: ["sk-stress-test"]),
    .executable(name: "sk-swiftc-wrapper", targets: ["sk-swiftc-wrapper"]),
    .executable(name: "sk-syntactic-perf", targets: ["sk-syntactic-perf"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.2.0"),
  ],
  targets: [
    .target(
        name: "CSourcekitd",
        dependencies: []),
    .target(
        name: "SwiftSourceKit",
        dependencies: ["CSourcekitd", "SKSupport", "Utility"]),
    .target(
        name: "SKSupport",
        dependencies: ["Utility"]),
    .target(
      name: "Common",
      dependencies: ["Utility"]),
    .target(
      name: "StressTester",
      dependencies: ["SwiftSourceKit", "Common", "Utility"]),
    .target(
      name: "SwiftCWrapper",
      dependencies: ["Common", "Utility"]),

    .target(
      name: "sk-stress-test",
      dependencies: ["StressTester"]),
    .target(
      name: "sk-swiftc-wrapper",
      dependencies: ["SwiftCWrapper"]),
    .target(
      name: "sk-syntactic-perf",
      dependencies: ["StressTester"]),

    .testTarget(
        name: "StressTesterToolTests",
        dependencies: ["SwiftSourceKit", "StressTester"]),
    .testTarget(
      name: "SwiftCWrapperToolTests",
      dependencies: ["SwiftCWrapper"])
  ]
)
