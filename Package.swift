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
            url: "https://github.com/ClassicalDude/pdfView-Freedraw/releases/download/v1.0/PDFFreedraw.xcframework.zip",
            checksum: "6b0987263d1e90988d3a69b0b8219deac592ad0b39b5c68171cc05af6f0be152"
        )
    ]
)

