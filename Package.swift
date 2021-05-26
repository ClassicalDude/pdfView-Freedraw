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
            url: "https://github.com/ClassicalDude/pdfView-Freedraw/releases/download/v1.1/PDFFreedraw.xcframework.zip",
            checksum: "5052d46fe871504d31216d3c8700611739ef142d4f283a8fda0caa277c2e0158"
        )
    ]
)

