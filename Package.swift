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
            checksum: "a0ad4f70cdaeca64d169b6bf219300ab0b73bffd4b1067332c17d37564db013a"
        )
    ]
)

