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
    private var annotation : PDFAnnotation! // The annotation we are actively drawing or deleting
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
                    self.erase(rect: rect, pointInPage: convertedPoint, currentPath: self.signingPath)
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
                    self.erase(rect: rect, pointInPage: convertedPoint, currentPath: self.signingPath)
                    // Remove the UIView for the CAShapeLayer
//                        for drawVeilSubview in self.pdfView!.superview!.subviews.filter({$0.tag==35791}) {
//                            drawVeilSubview.removeFromSuperview()
//                        }
//                        self.viewPath.removeAllPoints()

                } else {
                    
                    // Check if we created a circle. If we did, and the class variable for this is true, get a revised path.
                    
                    if self.convertClosedCurvesToOvals, self.testForClosedCurve(path: self.signingPath), PDFFreedrawGestureRecognizer.inkType != .eraser {
                        self.signingPath = self.ovalFromClosedCurve(rect: rect)
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
                    self.currentPDFPage.addAnnotation(self.annotation)
                    self.registerUndo()
                    
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    self.viewPath.removeAllPoints()
                }
            }
        }
    }
    
    // MARK: Closed Curves to Perfect Ovals
    
    // Function that tests if the path is nearly closed and without straight lines
    private func testForClosedCurve(path: UIBezierPath) -> Bool {
        
        // Get the distance between the path's start and end point
        let vector = path.firstPoint().vector(to: path.lastPoint())
        let distance = sqrt(pow(vector.dx, 2) + pow(vector.dy, 2))
        if distance > 10 {
            return false
        }
        
        // Get the distances between each pair of adjacent points on the path. Return false if any of them is bigger than 20.
        let pathPoints = getPathPoints(path: path)
        for i in 0..<pathPoints.count-1 {
            let pathPointsVector = pathPoints[i].vector(to: pathPoints[i+1])
            let pathPointsDistance = sqrt(pow(pathPointsVector.dx, 2) + pow(pathPointsVector.dy, 2))
            if pathPointsDistance > 20 {
                return false
            }
        }
        return true
    }
    
    // Function that returns a perfect oval from a given rect as an open path - so that the eraser can work
    private func ovalFromClosedCurve(rect: CGRect) -> UIBezierPath {
        let initialOval = UIBezierPath(ovalIn: rect)
        return getOvalOpenPath(path: initialOval)
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
    
    private func erase(rect: CGRect, pointInPage: CGPoint, currentPath: UIBezierPath) {
        let annotations = self.pdfView?.currentPage?.annotations
        if (annotations?.count ?? 0) > 0 {
            for annotation in annotations! {
                // Initial test - intersection of the frames of the annotation and the current path. Continue only if true.
                if annotation.bounds.intersects(rect) {
                    if annotation.type == "Ink", let annotationPath = self.eraserTest(annotation: annotation, pointInPage: pointInPage) {
                        let strokedCurrentPath = currentPath.cgPath.copy(strokingWithWidth: 10.0, lineCap: .round, lineJoin: .round, miterLimit: 0)
                        let strokedCurrentBezierPath = UIBezierPath(cgPath: strokedCurrentPath)
                        //let intersectingPaths : NSArray = UIBezierPath.redAndGreenAndBlueSegmentsCreated(from: annotationPath, bySlicingWith: strokedCurrentBezierPath, andNumberOfBlueShellSegments: nil)! as NSArray
                        
                        //print (intersectingPaths as! [UIBezierPath])
                        
                        // Draw temporary annotation on screen using a CAShapeLayer, to be replaced later with the PDFAnnotation
                        var colorSelect = 0
                        let colors = [UIColor.red, UIColor.green, UIColor.blue, UIColor.purple, UIColor.gray]
                        //print (intersectingPaths.count)
                        //for tempPath in intersectingPaths {
                            //let testPaths : NSMutableArray = intersectingPaths[2] as! NSMutableArray
                            //print ("sub: \(testPaths.count)")
                            //for testPath in testPaths {
                                //print ((testPath as! DKUIBezierPathClippedSegment).startIntersection)
//                            let testPath = testPaths[0] as! DKUIBezierPathClippedSegment
                        //for path in annotationPath.difference(with: strokedCurrentBezierPath) {
                                let viewPathLayer = CAShapeLayer()
                                viewPathLayer.strokeColor = colors[colorSelect].cgColor
                                viewPathLayer.lineWidth = CGFloat(PDFFreedrawGestureRecognizer.width * self.pdfView!.scaleFactor)
                                //viewPathLayer.path = (testPath as! DKUIBezierPathClippedSegment).pathSegment.cgPath
                        let path1 = annotation.paths!.first!
                        let origin = self.pdfView!.superview!.convert(annotation.bounds.origin, from: pdfView!)
                        print ("page: \(self.pdfView!.currentPage?.annotations.first?.bounds.origin)")
                        let pdfPageOrigin = self.pdfView!.convert((self.pdfView!.currentPage?.annotations.first?.bounds.origin)!, from: self.pdfView!.currentPage!)
                        print ("pdfView: \(pdfPageOrigin)")
                        print ("view: \(self.pdfView!.superview!.convert(pdfPageOrigin, to: self.pdfView!.superview!))")
                        print ("page size: \(pdfView!.currentPage?.bounds(for: .cropBox))")
                        print ("view size: \(pdfView!.frame)")
                        print ("factor: \(pdfView!.scaleFactor)")
                        print (pdfView!.convert(pdfView!.currentPage!.bounds(for: .cropBox), from: pdfView!.currentPage!))
                        let pdfPageBounds = pdfView!.convert(pdfView!.currentPage!.bounds(for: .cropBox), from: pdfView!.currentPage!)
                        path1.apply(CGAffineTransform(scaleX: pdfView!.scaleFactor, y: -pdfView!.scaleFactor))
                        path1.apply(CGAffineTransform(translationX: origin.x*pdfView!.scaleFactor+pdfPageBounds.minX, y: self.pdfView!.bounds.height-pdfPageBounds.minY-origin.y*pdfView!.scaleFactor))
                        viewPathLayer.path = path1.cgPath
                            //viewPathLayer.path = path.cgPath
                                viewPathLayer.fillColor = UIColor.clear.cgColor
                                viewPathLayer.lineJoin = CAShapeLayerLineJoin.round
                                viewPathLayer.lineCap = CAShapeLayerLineCap.round

                                self.drawVeil.layer.addSublayer(viewPathLayer)
                                
                                colorSelect += 1
                                if colorSelect >= colors.count { colorSelect = 0 }
                            //}
                        //}
                        
                        self.pdfView?.currentPage?.removeAnnotation(annotation)
                        self.annotation = annotation // Make sure we register the right annotation
                        self.registerUndo()
                    }
                }
            }
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
    
    // Function that extracts all points from a UIBezierPath, using the Clipping Bezier library
    private func getPathPoints(path: UIBezierPath) -> [CGPoint] {
        var pathPoints : [CGPoint] = []
        var counter = path.elementCount
        if path.isClosed() {
            counter -= 1 // In a closed path, the last element does not have a point
        }
        for i in 0..<counter {
            pathPoints.append(path.element(at: i).points.pointee)
        }
        return pathPoints
    }
    
    // Function that extracts all points, including control points, from a UIBezierPath. The second part of the function is more specific: it creates an open path for curves created by the points.
    private func getOvalOpenPath(path: UIBezierPath) -> UIBezierPath {
        var bezierPoints = NSMutableArray()
        path.cgPath.apply(info: &bezierPoints, function: { info, element in

                guard let resultingPoints = info?.assumingMemoryBound(to: NSMutableArray.self) else {
                    return
                }

                let points = element.pointee.points
                let type = element.pointee.type

                switch type {
                case .moveToPoint:
                    resultingPoints.pointee.add([NSNumber(value: Float(points[0].x)), NSNumber(value: Float(points[0].y))])
                    resultingPoints.pointee.add(NSString("move"))

                case .addLineToPoint:
                    resultingPoints.pointee.add([NSNumber(value: Float(points[0].x)), NSNumber(value: Float(points[0].y))])
                    resultingPoints.pointee.add(NSString("addLine"))

                case .addQuadCurveToPoint:
                    resultingPoints.pointee.add([NSNumber(value: Float(points[0].x)), NSNumber(value: Float(points[0].y))])
                    resultingPoints.pointee.add([NSNumber(value: Float(points[1].x)), NSNumber(value: Float(points[1].y))])
                    resultingPoints.pointee.add(NSString("addQuadCurve"))

                case .addCurveToPoint:
                    resultingPoints.pointee.add([NSNumber(value: Float(points[0].x)), NSNumber(value: Float(points[0].y))])
                    resultingPoints.pointee.add([NSNumber(value: Float(points[1].x)), NSNumber(value: Float(points[1].y))])
                    resultingPoints.pointee.add([NSNumber(value: Float(points[2].x)), NSNumber(value: Float(points[2].y))])
                    resultingPoints.pointee.add(NSString("addCurve"))

                case .closeSubpath:
                    break
                @unknown default:
                    break
                }
            })
        let elementsTypes : [String] = bezierPoints.compactMap { $0 as? String }
        let elementsCGFloats : [[CGFloat]] = bezierPoints.compactMap { $0 as? [CGFloat] }
        var elementsCGPoints : [CGPoint] = elementsCGFloats.map { CGPoint(x: $0[0], y: $0[1]) }
        
        let ovalOpenPath = UIBezierPath()
        for i in 0..<elementsTypes.count {
            switch elementsTypes[i] {
            case "move":
                ovalOpenPath.move(to: elementsCGPoints.removeFirst())
            case "addCurve":
                let controlPoint1 = elementsCGPoints.removeFirst()
                let controlPoint2 = elementsCGPoints.removeFirst()
                let point = elementsCGPoints.removeFirst()
                ovalOpenPath.addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            default:
                break
            }
        }
        return ovalOpenPath
    }
        
    private func eraserTest(annotation: PDFAnnotation, pointInPage: CGPoint) -> UIBezierPath? {
        guard (annotation.paths?.count ?? 0) > 0 else { return nil }
        //let boundingRectOrigin = self.pdfView!.convert(CGPoint(x:annotation.bounds.origin.x, y:annotation.bounds.minY), from: pdfView!)
        let boundingRectOrigin = self.pdfView!.superview!.convert(annotation.bounds.origin, from: pdfView!)
        if let translatedPath = translate(path: annotation.paths!.first!.cgPath, by: boundingRectOrigin)?.copy(strokingWithWidth: 10.0, lineCap: .round, lineJoin: .round, miterLimit: 0) {
            if translatedPath.contains(pointInPage) {
                return UIBezierPath(cgPath: translate(path: annotation.paths!.first!.cgPath, by: boundingRectOrigin)!)
            }
        }
        return nil
    }
    
    private func translate(path : CGPath?, by point: CGPoint) -> CGPath? {
        let bezeirPath = UIBezierPath()
        guard let prevPath = path else {
            return nil
        }
        bezeirPath.cgPath = prevPath
        bezeirPath.apply(CGAffineTransform(translationX: point.x, y: point.y))

        return bezeirPath.cgPath
    }
}
