//
//  PDFFreedrawGestureRecognizer.swift
//  pdfView Freedraw
//
//  Created by Ron Regev on 02/10/2020.
//

import UIKit
import PDFKit

/// A protocol that allows delegates of `PDFFreedrawGestureRecognizer` to respond to changes in the undo state of the class object.
public protocol PDFFreedrawGestureRecognizerUndoDelegate {
    func freedrawUndoStateChanged()
}

class PDFFreedrawGestureRecognizer: UIGestureRecognizer {
    /// The color used by the free draw annotation
    public static var color = UIColor.red
    /// The line width of the free draw annotation
    public static var width : CGFloat = 3
    /// An enum defining the three options for free draw: pen, highlighter and eraser
    public enum FreedrawType {
        case pen
        case eraser
        case highlighter
    }
    /// The type of free draw annotation. Select between pen, highlighter and eraser
    public static var inkType : FreedrawType = .pen
    
    /// The number of annotations to keep in the undo history. The default is 10
    public var maxUndoNumber : Int = 10
    
    /// When `true`, closed and nearly-closed curves will be drawn as perfect ovals
    public var convertClosedCurvesToOvals = false
    
    /// Bool indicating whether there are annotations that can be undone
    public var canUndo = false
    
    /// Bool indicating whether there are annotations that can be redone
    public var canRedo = false
    
    public var undoDelegate : PDFFreedrawGestureRecognizerUndoDelegate?
    
    private var passedSafetyChecks = false // Used to record all of the unwrappings of touchesBegan
    private var drawVeil = UIView() // Used for temporary on a CAShapeLayer during touchesMoved
    private var startLocation : CGPoint? // Starting touch point for every touches function
    private var movedTest : CGPoint? // Used to compare locations between touchesBegan and touchesEnded, to ensure there actually was a moving gesture
    private var totalDistance : CGFloat = 0 // Used to measure overall distances between the touches functions, to ensure there was a moving gesture
    private var signingPath = UIBezierPath() // The path in the PDF page coordinate system
    private var viewPath = UIBezierPath() // The path in the UIView coordinate system
    private var pdfView : PDFView! // The view of the PDF document
    private var currentPDFPage : PDFPage! // Safely unwrapped variable used for the current PDF page
    private var annotation : PDFAnnotation! // The annotation path we are actively drawing or deleting
    private var annotationBeingErasedPath = UIBezierPath() // An annotation we are actively erasing
    private var originalAnnotationColor : UIColor! // Used to track the active PDF annotation color when it is hidden during the erasing process
    // Undo manager variables
    private var annotationsToUndo : [(PDFAnnotation, FreedrawType)] = []
    private var annotationsToRedo : [(PDFAnnotation, FreedrawType)] = []
    
    convenience init(color: UIColor?, width: CGFloat?, type: FreedrawType?) {
        PDFFreedrawGestureRecognizer.color = color ?? UIColor.red
        PDFFreedrawGestureRecognizer.width = width ?? 3
        PDFFreedrawGestureRecognizer.inkType = type ?? .pen
        self.init()
    }
    
    // MARK: Touches Began
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        // Perform safety checks and get the PDFView to annotate
        if let possiblePDFViews = self.view?.subviews.filter({$0 is PDFView}) {
            if possiblePDFViews.count > 1 {
                print ("PDFFreedrawGestureRecognizer cannot be attached to a view that has more than one PDFView as a subview")
                return
            } else if possiblePDFViews.count == 0 {
                print ("PDFFreedrawGestureRecognizer must be attached to a superview of a PDFView")
                return
            } else {
                pdfView = possiblePDFViews[0] as? PDFView
            }
        }
        
        // Check if the pdfView is user interaction enabled. Set that property to false in your view controller in order to disable drawing and resume regular pdfView gestures.
        if pdfView.isUserInteractionEnabled {
            return
        }
        
        // Check that we have a valid pdfDocument
        if pdfView.document == nil {
            print ("There is no document associated with the PDF view. Exiting PDFFreedrawGestureRecognizer")
        }
        
        // Check that we have a valid pdfPage and assign it to the class variable
        if let currentPDFPageTest = pdfView.document!.page(at: (pdfView.document!.index(for: (pdfView.currentPage ?? PDFPage())))) {
            currentPDFPage = currentPDFPageTest
        }
        
        // Record the fact that we got that far, to be used in touchesMoved and touchesEnded
        passedSafetyChecks = true
        
        if let touch = touches.first {
            
            DispatchQueue.main.async {
                
                // Attach the UIView that we will use to draw the annotation on a CALayer, until the touches end
                self.drawVeil = UIView(frame: self.pdfView.frame)
                self.drawVeil.tag = 35791 // For identifying and removing all instances later on
                self.drawVeil.isUserInteractionEnabled = false
                self.pdfView.superview!.addSubview(self.drawVeil)
                
                // movedTest will be used in touchedEnded to ascertain if we moved, or just tapped
                self.movedTest = touch.location(in: self.view)
                guard (self.movedTest != nil) else { return }
                
                // startLocation will be used for adding to the UIBezierPath
                self.startLocation = touch.location(in: self.pdfView)
                guard (self.startLocation != nil) else { return }
                self.totalDistance = 0
                
                // Clear and initialize the UIBezierPath used on the PDF page coordinate system
                self.signingPath = UIBezierPath()
                self.signingPath.move(to: self.pdfView!.convert(self.startLocation!, to: self.pdfView!.page(for: self.startLocation!, nearest: true)!))
                
                // Clear and initialize the UIBezierPath for the CAShapeLayer we will use during touchesMoved
                self.viewPath = UIBezierPath()
                self.viewPath.move(to: self.startLocation!)
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !passedSafetyChecks {
            return
        }
        
        if let touch = touches.first {
            DispatchQueue.main.async {
                
                // Test for minimal viable distance to register the move
                let currentLocation = touch.location(in: self.pdfView)
                let vector = currentLocation.vector(to: self.startLocation!)
                self.totalDistance += sqrt(pow(vector.dx, 2) + pow(vector.dy, 2))
                if self.totalDistance < 10.0 { // change the "10.0" to your value of choice if you wish to change the minimal viable distance
                    return
                }
                
                // Reset redo history after the touches started moving
                if self.annotationsToRedo.count > 0 {
                    self.annotationsToRedo.removeAll()
                    self.updateUndoRedoState()
                }
                
                // Get the current gesture location
                let position = touch.location(in: self.pdfView)
                let convertedPoint = self.pdfView!.convert(position, to: self.pdfView!.page(for: position, nearest: true)!)
                // Add line to the PDF annotation UIBezierPath
                self.signingPath.addLine(to: convertedPoint) // For the PDFAnnotation
                
                // Add line to the CAShapeLayer UIBezierPath
                self.viewPath.addLine(to: currentLocation)
                
                // Prevent crashes with very short gestures
                if self.signingPath.isEmpty {
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    return
                }
                
                // Create bounding rect for the annotation
                var rect = CGRect()
                if PDFFreedrawGestureRecognizer.inkType != .eraser {
                    // Change the rect to allow for lines wider than a point. Not needed for the eraser.
                    rect = CGRect(x:self.signingPath.bounds.minX-PDFFreedrawGestureRecognizer.width/2, y:self.signingPath.bounds.minY-PDFFreedrawGestureRecognizer.width/2, width:self.signingPath.bounds.maxX-self.signingPath.bounds.minX+PDFFreedrawGestureRecognizer.width, height:self.signingPath.bounds.maxY-self.signingPath.bounds.minY+PDFFreedrawGestureRecognizer.width)
                } else {
                    rect = self.signingPath.bounds
                }
                
                // Erase annotation if in eraser mode
                if PDFFreedrawGestureRecognizer.inkType == .eraser {
                    self.erase(rect: rect, pointInPage: convertedPoint, currentPDFPath: self.signingPath, currentUIViewPath: self.viewPath, calledFromTouchesEnded: false)
                } else {
                    
                    // Clear any remaining CAShapeLayer from the drawVeil. We cannot use the helper function here, because two DispatchQueues create a race condition.
                    if self.drawVeil.layer.sublayers != nil {
                        for layer in self.drawVeil.layer.sublayers! {
                            layer.removeFromSuperlayer()
                        }
                    }
                    
                    // Choose the transparency of the annotation based on its type
                    var alphaComponent : CGFloat = 1.0
                    if PDFFreedrawGestureRecognizer.inkType == .highlighter {
                        alphaComponent = 0.3
                    }
                    
                    // Draw temporary annotation on screen using a CAShapeLayer, to be replaced later with the PDFAnnotation
                    let viewPathLayer = CAShapeLayer()
                    viewPathLayer.strokeColor = PDFFreedrawGestureRecognizer.color.withAlphaComponent(alphaComponent).cgColor
                    viewPathLayer.lineWidth = CGFloat(PDFFreedrawGestureRecognizer.width * self.pdfView!.scaleFactor) // Note the use of the scale factor! Necessary for keeping this drawing identical to the final PDF annotation
                    viewPathLayer.path = self.viewPath.cgPath
                    viewPathLayer.fillColor = UIColor.clear.cgColor
                    viewPathLayer.lineJoin = CAShapeLayerLineJoin.round
                    viewPathLayer.lineCap = CAShapeLayerLineCap.round

                    self.drawVeil.layer.addSublayer(viewPathLayer)
                    
                    // Update the startLocation for touchesEnded below
                    self.startLocation = currentLocation
                }
            }
        }
    }
    
    // MARK: Touches Ended
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !passedSafetyChecks {
            return
        }
        
        if let touch = touches.first {
            DispatchQueue.main.async {
                
                // Test for minimal viable distance to register the move
                let currentLocation = touch.location(in: self.pdfView)
                let vector = currentLocation.vector(to: self.movedTest!)
                self.totalDistance += sqrt(pow(vector.dx, 2) + pow(vector.dy, 2))
                if self.totalDistance < 10.0 { // change the "10.0" to your value of choice if you wish to change the minimal viable distance
                    self.signingPath.removeAllPoints() // Prevent a short line when accessed from long tap
                }
                
                // Get the current gesture location
                let position = touch.location(in: self.pdfView)
                let convertedPoint = self.pdfView!.convert(position, to: self.pdfView!.page(for: position, nearest: true)!)
                
                // Append the move to the UIBezierPath of the PDF annotation.
                self.signingPath.addLine(to: convertedPoint)
                
                // Prevent crashes with very short gestures. This will also be called if we failed the distance check earlier, because the signing path was emptied.
                if self.signingPath.isEmpty {
                    self.viewPath.removeAllPoints()
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    return
                }
                
                // Create bounding rect for the annotation
                var rect = CGRect()
                if PDFFreedrawGestureRecognizer.inkType != .eraser {
                    // Change the rect to allow for lines wider than a point. Not needed for the eraser.
                    rect = CGRect(x:self.signingPath.bounds.minX-PDFFreedrawGestureRecognizer.width/2, y:self.signingPath.bounds.minY-PDFFreedrawGestureRecognizer.width/2, width:self.signingPath.bounds.maxX-self.signingPath.bounds.minX+PDFFreedrawGestureRecognizer.width, height:self.signingPath.bounds.maxY-self.signingPath.bounds.minY+PDFFreedrawGestureRecognizer.width)
                } else {
                    rect = self.signingPath.bounds
                }
                
                // Create a temporary PDF annotation for a framework workaround
                let currentAnnotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
            
                // Workaround for a bug in PDFKit - remove the annotation before you add it
                self.currentPDFPage.removeAnnotation(currentAnnotation)
                
                // Eraser
                if PDFFreedrawGestureRecognizer.inkType == .eraser {
                    self.erase(rect: rect, pointInPage: convertedPoint, currentPDFPath: self.signingPath, currentUIViewPath: self.viewPath, calledFromTouchesEnded: true)
                    // Remove the UIView for the CAShapeLayer
                    for drawVeilSubview in self.pdfView!.superview!.subviews.filter({$0.tag==35791}) {
                        drawVeilSubview.removeFromSuperview()
                    }
                    self.viewPath.removeAllPoints()

                } else {
                    
                    // Check if we created a circle. If we did, and the class variable for this is true, get a revised path.
                    
                    if self.convertClosedCurvesToOvals, self.signingPath.resemblesOval(), PDFFreedrawGestureRecognizer.inkType != .eraser {
                        self.signingPath = UIBezierPath(openOvalIn: rect)
                    }
                    
                    // Create the annotation we will save
                    self.annotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
                    let b = PDFBorder()
                    if PDFFreedrawGestureRecognizer.inkType != .eraser {
                        b.lineWidth = PDFFreedrawGestureRecognizer.width
                    } else {
                        b.lineWidth = 1
                    }
                    self.annotation.border = b
                    var alphaComponent : CGFloat = 1.0
                    if PDFFreedrawGestureRecognizer.inkType == .highlighter {
                        alphaComponent = 0.3
                    }
                    self.annotation.color = PDFFreedrawGestureRecognizer.color.withAlphaComponent(alphaComponent)
                    _ = self.signingPath.moveCenter(to: rect.center)
                    self.annotation.add(self.signingPath)
                    // Record the annotation type at a convenient metadata field
                    self.annotation.userName = "\(PDFFreedrawGestureRecognizer.inkType)"
                    self.currentPDFPage.addAnnotation(self.annotation)
                    self.registerUndo()
                    
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    self.viewPath.removeAllPoints()
                    
                    // Make sure the annotation is nil
                    self.annotation = nil
                }
            }
        }
    }
    
    // MARK: Undo Manager
    
    /// Function that registers the last annotation action in the undo history
    public func registerUndo() {
        annotationsToUndo.append((annotation, PDFFreedrawGestureRecognizer.inkType))
        if annotationsToUndo.count > maxUndoNumber {
            annotationsToUndo.removeFirst()
        }
        updateUndoRedoState()
    }
    
    private func updateUndoRedoState() {
        if annotationsToUndo.count > 0 {
            if canUndo == false {
                canUndo = true
                // The state changed. alert the delegate
                undoDelegate?.freedrawUndoStateChanged()
            }
        } else {
            if canUndo == true {
                canUndo = false
                // The state changed. alert the delegate
                undoDelegate?.freedrawUndoStateChanged()
            }
        }
        if annotationsToRedo.count > 0 {
            if canRedo == false {
                canRedo = true
                // The state changed. alert the delegate
                undoDelegate?.freedrawUndoStateChanged()
            }
        } else {
            if canRedo == true {
                canRedo = false
                // The state changed. alert the delegate
                undoDelegate?.freedrawUndoStateChanged()
            }
        }
    }
    
    /// Undo annotations by order of creation, up to the number set by `maxUndoNumber`
    public func undoAnnotation() {
        let annotationToRemove = annotationsToUndo.popLast()
        guard annotationToRemove != nil else { return }
        if annotationToRemove?.1 != .eraser {
            DispatchQueue.main.async {
                self.pdfView?.document?.page(at: (self.pdfView?.document?.index(for: (self.pdfView?.currentPage!)!))!)?.removeAnnotation((annotationToRemove?.0)!)
            }
        } else {
            DispatchQueue.main.async {
                self.pdfView?.document?.page(at: (self.pdfView?.document?.index(for: (self.pdfView?.currentPage!)!))!)?.addAnnotation((annotationToRemove?.0)!)
            }
        }
        annotationsToRedo.append(annotationToRemove!)
        updateUndoRedoState()
    }
    
    /// Redo annotations by reverse order of undoing
    public func redoAnnotation() {
        let annotationToRestore = annotationsToRedo.popLast()
        guard annotationToRestore != nil else { return }
        if annotationToRestore?.1 != .eraser {
            DispatchQueue.main.async {
                self.pdfView?.document?.page(at: (self.pdfView?.document?.index(for: (self.pdfView?.currentPage!)!))!)?.addAnnotation((annotationToRestore?.0)!)
            }
        } else {
            DispatchQueue.main.async {
                self.pdfView?.document?.page(at: (self.pdfView?.document?.index(for: (self.pdfView?.currentPage!)!))!)?.removeAnnotation((annotationToRestore?.0)!)
            }
        }
        annotationsToUndo.append(annotationToRestore!)
        updateUndoRedoState()
    }
    
    // MARK: Eraser
    
    private func erase(rect: CGRect, pointInPage: CGPoint, currentPDFPath: UIBezierPath, currentUIViewPath: UIBezierPath, calledFromTouchesEnded: Bool) {
        let annotations = currentPDFPage.annotations
        guard annotations.count > 0 else { return }
        for annotation in annotations {
            // Initial test - intersection of the frames of the annotation and the current path, which is a very cheap test. Continue only if true.
            guard annotation.bounds.intersects(rect) else { continue }
            
            // Test a specific hit test for the point of intersection. More expensive.
            guard annotation.hitTest(pdfView: pdfView, pointInPage: pointInPage) ?? false else { continue }
            
            // Deal with non-ink annotations by simply erasing them
            if annotation.type != "Ink" {
                
                guard annotation.hitTest(pdfView: pdfView, pointInPage: pointInPage) ?? false else { continue }
                currentPDFPage.removeAnnotation(annotation)
                continue
            }
            
            // Check if our class annotation variable is non-nil, and different than the one we just detected. If it is, then it is time to split the PDF annotation path on the PDF page and remove its intersection with the eraser. This is also necessary if we just lifted our finger.
            if self.annotation != nil && (self.annotation == annotation || calledFromTouchesEnded) {
                
//                // Fatten the eraser and stroke its path, so that we can detect the intersection
//                let eraserPath = UIBezierPath(cgPath: currentPDFPath.cgPath.copy(strokingWithWidth: 40.0/pdfView.scaleFactor, lineCap: .round, lineJoin: .round, miterLimit: 0))
//
//                // Define our annotation path
//                let annotationPath = self.annotation.paths!.first!
//                //let annotationPath = UIBezierPath(cgPath: self.annotation.paths!.first!.cgPath.copy(strokingWithWidth: 10.0, lineCap: .round, lineJoin: .round, miterLimit: 0))
//                // Get annotation rect origin
//                let origin = annotation.bounds.origin
//                // Get the PDF page bounds, converted to UIView coordinates
//                let pdfPageBounds = currentPDFPage.bounds(for: .cropBox)
//                // Apply transformations to the annotation path from PDF coordinates to UIView coordinates
//                //annotationBeingErasedPath.apply(CGAffineTransform(scaleX: pdfView.scaleFactor, y: -pdfView.scaleFactor))
//                annotationPath.apply(CGAffineTransform(translationX: origin.x + pdfPageBounds.minX, y: pdfView.bounds.height - pdfPageBounds.minY - origin.y))
//
//                // Use Clipping Bezier to calculate the difference between the annotation and the eraser
//                let erasedAnnotationPaths = eraserPath.difference(with: annotationPath)
//                print (erasedAnnotationPaths)
//                if erasedAnnotationPaths?.count ?? 0 == 0 { return }
//                let erasedAnnotationPath = erasedAnnotationPaths!.first!
//
//                DispatchQueue.main.async {
//                    // Remove the original annotation from the page
//                    self.currentPDFPage.removeAnnotation(self.annotation)
//                    // Restore its color
//                    self.annotation.color = self.originalAnnotationColor
//                    // Clear the stored color
//                    self.originalAnnotationColor = UIColor.clear
//                    // Manually add this annotation to the undo stack
//                    var inkTypeToRecord : FreedrawType = .pen
//                    switch self.annotation.userName {
//                    case "highlighter":
//                        inkTypeToRecord = .highlighter
//                    default:
//                        inkTypeToRecord = .pen
//                    }
//                    self.annotationsToUndo.append((annotation, inkTypeToRecord))
//
//                    // Add the replacement annotation
//                    let replacementAnnotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
//                    _ = erasedAnnotationPath.moveCenter(to: rect.center)
//                    replacementAnnotation.add(erasedAnnotationPath)
//                    replacementAnnotation.border = self.annotation.border
//                    replacementAnnotation.color = self.annotation.color
//                    self.currentPDFPage.addAnnotation(replacementAnnotation)
//
//                    // Make the class annotation into the replacement annotation, for the sake of undo registration
//                    self.annotation = replacementAnnotation
//                    self.registerUndo()
//
//                    // Make the class annotation nil
//                    self.annotation = nil
//
//                    // Remove the CAShapeLayer
//                    if self.drawVeil.layer.sublayers != nil {
//                        for layer in self.drawVeil.layer.sublayers! {
//                            layer.removeFromSuperlayer()
//                        }
//                    }
//
//                    return
//                }
    
                self.annotation = nil
                print ("3")
                continue
            }
            
            // If we got here, this means we have already saved any previously-dealt-with erased annotations to the PDF page, and it is time to start erasing a new one.
            // First, if this is the first time we are encountering this annotation (the class variable is nil), let's translate its path to the UIView coordinates.
            if self.annotation == nil {
                print ("1")
                // Read the original annotation path, unwrap it, assign it to the class variable
                if let annotationPathUnwrapped = annotation.paths?.first {
                    annotationBeingErasedPath = annotationPathUnwrapped
                } else { continue }
                // Get annotation rect origin, converted to UIView coordinates
                let origin = pdfView.superview!.convert(annotation.bounds.origin, from: pdfView)
                // Get the PDF page bounds, converted to UIView coordinates
                let pdfPageBounds = pdfView.convert(currentPDFPage.bounds(for: .cropBox), from: currentPDFPage)
                // Apply transformations to the annotation path from PDF coordinates to UIView coordinates
                annotationBeingErasedPath.apply(CGAffineTransform(scaleX: pdfView.scaleFactor, y: -pdfView.scaleFactor))
                annotationBeingErasedPath.apply(CGAffineTransform(translationX: origin.x*pdfView.scaleFactor + pdfPageBounds.minX, y: pdfView.bounds.height - pdfPageBounds.minY - origin.y*pdfView.scaleFactor))
                
                // Set the class variable for the annotation, so we don't do this again until we are dealing with a different annotation
                self.annotation = annotation
                
                // Record its color, because we are about to hide it for the duration of drawing on the CAShapeLayer
                self.originalAnnotationColor = annotation.color
            }
            
            // The previous block is only called once per annotation. The current path is updated every time this function is called. Let's get the difference between them. The Clipping Bezier library will handle that calculation.
        
            // Fatten the eraser and stroke its path, so that we can detect the intersection
            let eraserPath = UIBezierPath(cgPath: currentUIViewPath.cgPath.copy(strokingWithWidth: 40.0, lineCap: .round, lineJoin: .round, miterLimit: 0))
            let erasedAnnotationPaths = annotationBeingErasedPath.difference(with: eraserPath)
            if erasedAnnotationPaths?.count ?? 0 == 0 { continue }
            let erasedAnnotationPath = erasedAnnotationPaths!.first!
            
            // Draw temporary annotation on screen using a CAShapeLayer, to be replaced later with the PDFAnnotation
            //DispatchQueue.main.async {
                
                // First, clear any existing layers
                if self.drawVeil.layer.sublayers != nil {
                    for layer in self.drawVeil.layer.sublayers! {
                        layer.removeFromSuperlayer()
                    }
                }
                
                // Time to draw
                let viewPathLayer = CAShapeLayer()
                viewPathLayer.strokeColor = self.originalAnnotationColor.cgColor
                viewPathLayer.lineWidth = CGFloat((self.annotation.border?.lineWidth ?? PDFFreedrawGestureRecognizer.width) * self.pdfView.scaleFactor)
                viewPathLayer.path = erasedAnnotationPath.cgPath
                viewPathLayer.fillColor = UIColor.clear.cgColor
                viewPathLayer.lineJoin = CAShapeLayerLineJoin.round
                viewPathLayer.lineCap = CAShapeLayerLineCap.round

                self.drawVeil.layer.addSublayer(viewPathLayer)
                
                // Hide the original annotation if it is not already hidden
                if self.annotation.color != UIColor.clear {
                    self.annotation.color = UIColor.red
                }
            //}
        }
    }
    
    // MARK: Helper Functions
    // Function that clears any CAShape sublayers of the UIView
    private func clearCAShapeLayer() {
        DispatchQueue.main.async {
            if self.drawVeil.layer.sublayers != nil {
                for layer in self.drawVeil.layer.sublayers! {
                    layer.removeFromSuperlayer()
                }
            }
        }
    }
    
    // Function that removes the drawVeil
    private func removeDrawVeil() {
        DispatchQueue.main.async {
            for drawVeilSubview in self.pdfView.superview!.subviews.filter({$0.tag==35791}) {
                drawVeilSubview.removeFromSuperview()
            }
        }
    }
}
