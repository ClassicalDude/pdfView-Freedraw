# pdfView Freedraw - Free Draw for iOS and iPadOS PDFKit
PDFFreedrawGestureRecognizer is a subclass of UIGestureRecognizer, which allows you to use a pen, a highlighter and an eraser on a PDFView page. It uses a CAShapeLayer for drawing the annotation on screen, and applies the PDFAnnotation to the page only when touchesEnded is called.

## Requirements
iOS or iPadOS 11 or higher, a PDF document loaded through PDFKit

## Installation
For the time being, download the entire project to test it.

To use the class in your project, you will need to include PDFFreedrawGestureRecognizer.swift and UIBezierPath+.swift.

## Branches
The main branch includes support for multiple undo/redo actions. Switch to the simpleUndo branch for a redo/undo toggle for the last action only.

## Usage
Please consult the ViewController.swift file.
