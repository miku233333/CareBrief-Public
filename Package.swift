// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "CareBrief",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "CareBriefCore", targets: ["CareBriefCore"]),
    .library(name: "CareBriefAppSupport", targets: ["CareBriefAppSupport"]),
    .executable(name: "carebrief-demo", targets: ["CareBriefDemo"]),
  ],
  targets: [
    .target(name: "CareBriefCore"),
    .target(
      name: "CareBriefAppSupport",
      dependencies: ["CareBriefCore"],
      path: "Apps/CareBriefAppSupport"
    ),
    .executableTarget(
      name: "CareBriefDemo",
      dependencies: ["CareBriefCore"]
    ),
    .testTarget(
      name: "CareBriefCoreTests",
      dependencies: ["CareBriefCore"]
    ),
    .testTarget(
      name: "CareBriefAppSupportTests",
      dependencies: ["CareBriefAppSupport", "CareBriefCore"],
      path: "Apps/CareBriefAppSupportTests"
    ),
  ],
  swiftLanguageVersions: [.v5]
)
