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
            url: "https://github.com/ClassicalDude/pdfView-Freedraw/releases/download/v0.1/PDFFreedraw.xcframework.zip",
            checksum: "f0353c8bbbcd2829a2e0a7bb32cafc0baefd1f6c7b7570d90ba3776052c32363"
        )
    ]
)

