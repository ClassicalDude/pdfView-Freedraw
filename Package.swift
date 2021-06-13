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
            url: "https://github.com/ClassicalDude/pdfView-Freedraw/releases/download/v1.2/PDFFreedraw.xcframework.zip",
            checksum: "db0c013df9f5964f23327a9d64b5dda2bdca53e450ec0c82f0b0c5cf169342b6"
        )
    ]
)

