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
            url: "https://github.com/ClassicalDude/pdfView-Freedraw/releases/download/v1.2.1/PDFFreedraw.xcframework.zip",
            checksum: "be1b7f8c80c77f83d1e137a0f1de32a2e7a55ec349e3c52237ad8e60855e213a"
        )
    ]
)

