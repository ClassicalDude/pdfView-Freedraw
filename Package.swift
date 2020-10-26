//
//  Package.swift
//  pdfView Freedraw
//
//  Created by Ron Regev on 26/10/2020.
//

import PackageDescription

//.target(
//   name: "ClippingBezier",
//   dependencies: [],
//   path: "ClippingBezier/",
//   exclude: ["pdfView Freedraw"],
//   cSettings: [
//      .headerSearchPath("Headers"),
//   ]
//),
//.target(
//    name: "pdfView Freedraw",
//    dependencies: ["ClippingBezier"],
//    path: "pdfView Freedraw"
//    sources: ["PDFFreedrawGestureRecognizer.swift", "FreedrawExtensions.swift", "UIBezierPath+.swift"]
//),

let package = Package(
  name: "pdfView Freedraw",
  products: [
    .library(name: "pdfView Freedraw", targets: ["pdfView Freedraw"])
  ],
  dependencies: [],
  targets: [
    .target(name: "ClippingBezier", dependencies: [], path: "ClippingBezier/", exclude: ["pdfView Freedraw"], cSettings: [.headerSearchPath("Headers")]),
    .target(name: "pdfView Freedraw", dependencies: ["ClippingBezier"], path: "pdfView Freedraw", sources: ["PDFFreedrawGestureRecognizer.swift", "FreedrawExtensions.swift", "UIBezierPath+.swift"])
  ]
)
