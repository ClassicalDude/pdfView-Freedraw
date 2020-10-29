
# pdfView Freedraw - Free Draw for iOS and iPadOS PDFKit

<p align="center">
  <img width="270" height="480" src="demo/demo.gif">
</p>

PDFFreedrawGestureRecognizer is a subclass of UIGestureRecognizer, which allows you to use a pen, a highlighter and an eraser on a PDFView page. It optimizes performance by using a CAShapeLayer for drawing the annotation on screen, and applies an ink-type PDFAnnotation to the page only when touchesEnded is called.

The class includes an undo manager and an eraser that can be used on all types of PDF annotations - including ones not created by the class.

Special features include the ability to snap roughly-drawn ovals into perfect ovals, and a precise eraser for ink-type annotations (rather than just erasing the whole annotation in one go).

## Requirements
- OS: iOS or iPadOS 11 or higher. Can be used on macOS through Catalyst. 
- PDF document loaded through PDFKit.

## Installation
- You can explore the functionality by downloading the entire project and testing the app.
- An xcframework is available at the release page. It is compiled for physical devices, simulator and catalyst.
- A swift package of the xcframework is available. To add the package to your project, use the address https://github.com/ClassicalDude/pdfView-Freedraw

## Usage
Please consult the ViewController.swift file.
