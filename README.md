
# pdfView Freedraw - Free Draw for iOS and iPadOS PDFKit

<p align="center">
  <img width="270" height="480" src="demo/demo.gif">
</p>

<code>PDFFreedrawGestureRecognizer</code> is a subclass of <code>UIGestureRecognizer</code>, which allows you to use a pen, a highlighter and an eraser on a <code>PDFView</code> page. It optimizes performance by using a <code>CAShapeLayer</code> for drawing the annotation on screen, and applies an ink-type <code>PDFAnnotation</code> to the page only when touchesEnded is called.

The class includes an undo manager and an eraser that can be used on all types of PDF annotations - including ones not created by the class.

Special features include the ability to snap roughly-drawn ovals into perfect ovals, and a precise eraser for ink-type annotations (rather than just erasing the whole annotation in one go).

## Requirements
- OS: The demo app can run on iOS or iPadOS 11 or higher. The xcframework can also be used on macOS through Catalyst. 
- PDF document loaded through <code>PDFKit</code>.

## Installation
- You can explore the functionality by downloading the entire project and testing the app.
- An xcframework is available at the [release page](https://github.com/ClassicalDude/pdfView-Freedraw/releases). It is compiled for physical devices, simulator and catalyst.
- A swift package of the source code and the compiled xcframework is available. To add the package to your project, use the address https://github.com/ClassicalDude/pdfView-Freedraw

When manually embedding the xcframework in your project, you must go the General tab of the target's settings and add it to the Frameworks, Libraries and Embedded Content section. Make sure you choose to embed and sign it:
<p align="center">
  <img width="640" height="427" src="demo/embedding.png">
</p>

After that you can add <code>import PDFFreedraw</code> to the relevant class in your project.

## Usage
Please consult the ViewController.swift file.

## Credit
The precise eraser for ink-type annotations is made possible by using the [ClippingBezier library](https://github.com/adamwulf/ClippingBezier) from Adam Wulf.
