// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OpenLensCore", defaultLocalization: "en", platforms: [.iOS(.v15)], products: [.library(name: "OpenLensCore", targets: ["OpenLensCore"])], targets: [.target(name: "OpenLensCore", path: "ios/example", sources: ["OpenLensText.swift"]), .testTarget(name: "OpenLensCoreTests", dependencies: ["OpenLensCore"], path: "Tests/OpenLensCoreTests")])
