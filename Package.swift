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
            url: "https://www.dropbox.com/s/jo792e00gmqw6rt/PDFFreedraw.xcframework.zip",
            checksum: "90bfe69494ebe24181d025c2ec738c42ea123738ba37e4ec2234980bad32973b"
        )
    ]
)

