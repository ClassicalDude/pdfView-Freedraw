// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "PDFFreedraw",
    products: [
        .library(name: "PDFFreedraw", targets: ["PDFFreedraw"])
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(
            name: "PDFFreedraw",
            url: "http://www.ronregev.com/ScoreWizard/PDFFreedraw.xcframework.zip",
            checksum: "34ab171fed4421f2ad29f2475586f36a20667a5b4bcf514ed6e4d629a1a2481d"
        )
    ]
)
