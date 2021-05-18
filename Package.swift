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
            checksum: "fc5fd61c2b71c10c78bddd5b5bf763e31ce7177fabdbacb89c59eb5e3e4b6f1c"
        )
    ]
)

