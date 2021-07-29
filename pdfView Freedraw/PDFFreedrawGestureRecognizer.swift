//
//  PDFFreedrawGestureRecognizer.swift
//  pdfView Freedraw
//
//  Created by Ron Regev on 02/10/2020.
//

import UIKit
import PDFKit
//import ClippingBezier // to be used when building framework
//import PerformanceBezier // to be used when building framework

/// A protocol that allows delegates of `PDFFreedrawGestureRecognizer` to respond to changes in the drawing state and the undo state of the class object.
public protocol PDFFreedrawGestureRecognizerDelegate {
    func freedrawStateChanged(isDrawing: Bool)
    func freedrawUndoStateChanged()
}

// This extension makes the freedrawStateChanged function an optional one by giving a default value
extension PDFFreedrawGestureRecognizerDelegate {
    func freedrawStateChanged(isDrawing: Bool) { }
}

/// A UIGestureRecognizer class for free-drawing ink PDF annotations and erasing all annotations.
public class PDFFreedrawGestureRecognizer: UIGestureRecognizer {
    /// The color used by the free-draw annotation. The default is red.
    public var color = UIColor.red
    /// The line width of the free-draw annotation. The default is 3.
    public var width : CGFloat = 3
    /// An enum defining the three types of free-draw: pen, highlighter and eraser.
    public enum FreedrawType {
        case pen
        case eraser
        case highlighter
    }
    /// The type of free-draw annotation. Select between pen, highlighter and eraser.
    public var inkType : FreedrawType = .pen
    
    /// The alpha component of the free-draw highlighter. The default is 0.3.
    public var highlighterAlphaComponent : CGFloat = 0.3
    
    /// The number of annotations per page to keep in the undo history. The default is 10.
    public var maxUndoNumber : Int = 10
    
    /// When `true`, closed and nearly-closed curves will be drawn as perfect ovals
    public var convertClosedCurvesToOvals = false
    
    /// Bool indicating whether there are annotations that can be undone in the current page.
    public private(set) var canUndo = false
    
    /// Bool indicating whether there are annotations that can be redone in the current page.
    public private(set) var canRedo = false
    
    /// Bool indicating whether the eraser should try to split ink annotation paths (`true`) or delete ink annotations as whole (`false`), similarly to all other annotations
    public var eraseInkBySplittingPaths = true
    
    /// A factor applied to the stroke width of the eraser
    public var eraserStrokeWidthFactor : CGFloat = 1.0
    
    /// Setting this to `true` will allow the class to function when `pdfView.displayMode != .singlePage`, `!pdfView.translatesAutoresizingMaskIntoConstraints` and `pdfView.contentMode != .scaleAspectFit` - this is not recommended
    public var disablePDFViewChecks = false
    
    /// As of iOS14 and iPadOS14, PDFKit does not load saved curved annotation paths properly. Setting this variable to `true` will store a copy of the original path in the annotation's `/Content` key of its metadata dictionary, to be recovered by `Annotation.getPath()`
    public var storeCurvedAnnotationPathsInMetadata = false
    
    public var freedrawDelegate : PDFFreedrawGestureRecognizerDelegate?
    
    private var passedSafetyChecks = false // Used to record all of the unwrappings and conditions of touchesBegan
    private var drawVeil = UIView() // Used for temporary canvas drawing on a CAShapeLayer during touchesMoved
    private var startLocation : CGPoint? // Starting touch point for every touches function
    private var movedTest : CGPoint? // Used to compare locations between touchesBegan and touchesEnded, to ensure there actually was a moving gesture
    private var totalDistance : CGFloat = 0 // Used to measure overall distances between the touches functions, to ensure there was a moving gesture
    private var signingPath = UIBezierPath() // The gesture path in the PDF page coordinate system
    private var viewPath = UIBezierPath() // The gesture path in the UIView coordinate system
    private var pdfView : PDFView! // The view of the PDF document
    private var currentPDFPage : PDFPage! // Safely unwrapped variable used for the current PDF page
    private var annotation : PDFAnnotation! // The annotation we are actively drawing or deleting
    private var annotationBeingErasedPath = UIBezierPath() // An annotation path we are actively erasing
    private var erasedAnnotationPath = UIBezierPath() // A split path created from intersection of the original annotation path and the eraser gesture path
    private var originalAnnotationColor : UIColor! // Used to track the active PDF annotation color when it is hidden during the erasing process
    private var firstTouchDetected : String? // Used to record the UUID of the first touch detected in touchesBegan, to prevent issues with multiple touch
    private var isValidTouch = false // Used to in conjunction with the previous var to record the validity of the touch between touchesBegan, touchesMoved and touchesEnded
    
    // Undo manager undo and redo histories. The Int refers to the page number. Usually only one annotation is recorded in the internal array. Two are recorded only when erasing an annotation by splitting its path - the original one and the split-path one.
    private var annotationsToUndo : [Int : [[PDFAnnotation?]]] = [:]
    private var annotationsToRedo : [Int : [[PDFAnnotation?]]] = [:]
    
    // The recomended init for using the class
    public convenience init(color: UIColor?, width: CGFloat?, type: FreedrawType?) {
        self.init()
        self.color = color ?? UIColor.red
        self.width = width ?? 3
        self.inkType = type ?? .pen
    }
    
    // Get the pdfView, pdfDocument and pdfPage for the class. This is called both from touchesBegan and from updateUndoRedoState. Returns true only if successful in getting all three, in which case their class variables are safe to forcibly unwrap.
    private func getCurrentPage() -> Bool {
        if let possiblePDFViews = self.view?.subviews.filter({$0 is PDFView}) {
            if possiblePDFViews.count > 1 {
                print ("PDFFreedrawGestureRecognizer cannot be attached to a view that has more than one PDFView as a subview")
                return false
            } else if possiblePDFViews.count == 0 {
                print ("PDFFreedrawGestureRecognizer must be attached to a superview of a PDFView")
                return false
            } else {
                pdfView = possiblePDFViews[0] as? PDFView
            }
        }
        
        // Check that we have a valid pdfDocument
        if pdfView.document == nil {
            // The next print statement should be turned off if you are using a pdf page change notification to trigger updateUndoRedoState - otherwise it will fire when you launch the app.
            // print ("There is no document associated with the PDF view. Exiting PDFFreedrawGestureRecognizer")
            return false
        }
        
        // Check that we have a valid pdfPage and assign it to the class variable
        if let currentPDFPageTest = pdfView.document!.page(at: (pdfView.document!.index(for: (pdfView.currentPage ?? PDFPage())))) {
            currentPDFPage = currentPDFPageTest
        } else {
            print ("Could not unwrap the current PDF page. Exiting PDFFreedrawGestureRecognizer")
            return false
        }
        return true
    }
    
    // MARK: Touches Began
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        // Perform safety checks and get the PDFView on which we will annotate
        passedSafetyChecks = false
        
        // Verify and populate our pdfView, pdfDocument and pdfPage
        if !getCurrentPage() {
            return
        }
        
        // Check if the pdfView is user interaction enabled. Set that property to false in your view controller in order to disable drawing and resume regular pdfView gestures.
        if pdfView.isUserInteractionEnabled {
            return
        }
        
        // Check that the pdfView options allow for reliable functionality, and alert the developer
        if !disablePDFViewChecks && (pdfView.displayMode != .singlePage || !pdfView.translatesAutoresizingMaskIntoConstraints || pdfView.contentMode != .scaleAspectFit) {
            print ("Current pdfView display options will prevent reliable functionality of PDFFreedrawGestureRecognizer. Please consult documentation. You can set the disablePDFViewChecks variable to true to continue anyway. Exiting.")
            return
        }
        
        // Record the fact that we got that far, to be used in touchesMoved and touchesEnded
        passedSafetyChecks = true
        
        // Deal with the touch gesture
        if let touch = event?.allTouches?.first, event!.allTouches!.count == 1 {
            // Record the first touch's uuid
            firstTouchDetected = String(format: "%p", touch)
            isValidTouch = false
            
            DispatchQueue.main.async { // Anything that requires drawing on screen should happen on the main thread
                
                // Attach the UIView that we will use for temporarily drawing the annotation on a CAShapeLayer, until the touchesEnded phase
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
                self.totalDistance = 0 // For checking later on that the gesture is significant
                
                // Clear and initialize the UIBezierPath used on the PDF page coordinate system
                self.signingPath = UIBezierPath()
                // Move the path to a starting point in the PDF page coordinate system
                self.signingPath.move(to: self.pdfView.convert(self.startLocation!, to: self.pdfView.page(for: self.startLocation!, nearest: true)!))
                
                // Clear and initialize the UIBezierPath for the CAShapeLayer we will use during touchesMoved
                self.viewPath = UIBezierPath()
                self.viewPath.move(to: self.startLocation!)
            }
        }
    }
    
    // MARK: Touches Moved
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !passedSafetyChecks {
            return
        }
        
        if let touch = event?.allTouches?.filter({String(format: "%p", $0)==self.firstTouchDetected}).first {
            
            DispatchQueue.main.async {
                
                // Test for minimal viable distance to register the move
                let currentLocation = touch.location(in: self.pdfView) // Current finger location on screen
                if self.isValidTouch == false {
                    let vector = currentLocation.vector(to: self.startLocation!)
                    self.totalDistance += sqrt(pow(vector.dx, 2) + pow(vector.dy, 2))
                    if self.totalDistance < 10.0 { // change the "10.0" to your value of choice if you wish to change the minimal viable distance
                        return
                    } else {
                        self.isValidTouch = true
                        // Alert the delegate that drawing has commenced
                        self.freedrawDelegate?.freedrawStateChanged(isDrawing: true)
                    }
                }
                
                // Reset redo history after the touches started moving
                if self.annotationsToRedo.count > 0 {
                    self.annotationsToRedo.removeAll()
                    self.updateUndoRedoState() // Update the delegate so it can change the button states
                }
                
                // Convert the current finger location to the PDF page coordinate system
                let convertedPoint = self.pdfView.convert(currentLocation, to: self.pdfView.page(for: currentLocation, nearest: true)!)
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
                if self.inkType != .eraser {
                    // Change the rect to allow for lines wider than a point. Not needed for the eraser.
                    rect = CGRect(x:self.signingPath.bounds.minX-self.width/2, y:self.signingPath.bounds.minY-self.width/2, width:self.signingPath.bounds.maxX-self.signingPath.bounds.minX+self.width, height:self.signingPath.bounds.maxY-self.signingPath.bounds.minY+self.width)
                } else {
                    rect = self.signingPath.bounds
                }
                
                // Erase annotation if in eraser mode
                if self.inkType == .eraser {
                    self.erase(rect: rect, pointInPage: convertedPoint, currentUIViewPath: self.viewPath)
                } else {
                    
                    // Clear any remaining CAShapeLayer from the drawVeil.
                    if self.drawVeil.layer.sublayers != nil {
                        for layer in self.drawVeil.layer.sublayers! {
                            layer.removeFromSuperlayer()
                        }
                    }
                    
                    // Choose the transparency of the annotation based on its type
                    var alphaComponent : CGFloat = 1.0
                    if self.inkType == .highlighter {
                        alphaComponent = self.highlighterAlphaComponent
                    }
                    
                    // Draw temporary annotation on screen using a CAShapeLayer, to be replaced later with the PDFAnnotation
                    let viewPathLayer = CAShapeLayer()
                    viewPathLayer.strokeColor = self.color.withAlphaComponent(alphaComponent).cgColor
                    viewPathLayer.lineWidth = CGFloat(self.width * self.pdfView.scaleFactor) // Note the use of the scale factor! Necessary for keeping this drawing identical to the final PDF annotation
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
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !passedSafetyChecks {
            // Alert the delegate that drawing has ended
            freedrawDelegate?.freedrawStateChanged(isDrawing: false)
            return
        }
        
        if let touch = touches.filter({String(format: "%p", $0)==self.firstTouchDetected}).first {
            DispatchQueue.main.async {
                
                // Test for minimal viable distance to register the move
                let currentLocation = touch.location(in: self.pdfView)
                let vector = currentLocation.vector(to: self.movedTest!)
                self.totalDistance += sqrt(pow(vector.dx, 2) + pow(vector.dy, 2))
                if self.totalDistance < 10.0 { // change the "10.0" to your value of choice if you wish to change the minimal viable distance. Remember to be consistent with touchesMoved
                    self.signingPath.removeAllPoints() // Prevent a short line when accessed from long tap
                    self.viewPath.removeAllPoints()
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    return
                }
                
                // Convert the current finger location to the PDF page coordinate system
                let convertedPoint = self.pdfView.convert(currentLocation, to: self.pdfView.page(for: currentLocation, nearest: true)!)
                
                // Add line to the PDF annotation UIBezierPath
                self.signingPath.addLine(to: convertedPoint)
                
                // Prevent crashes with very short gestures
                if self.signingPath.isEmpty {
                    self.viewPath.removeAllPoints()
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    return
                }
                
                // Create bounding rect for the annotation
                var rect = CGRect()
                if self.inkType != .eraser {
                    // Change the rect to allow for lines wider than a point. Not needed for the eraser.
                    rect = CGRect(x:self.signingPath.bounds.minX-self.width/2, y:self.signingPath.bounds.minY-self.width/2, width:self.signingPath.bounds.maxX-self.signingPath.bounds.minX+self.width, height:self.signingPath.bounds.maxY-self.signingPath.bounds.minY+self.width)
                } else {
                    rect = self.signingPath.bounds
                }
                
                // Create a temporary PDF annotation for a PDFKit bug workaround
                let currentAnnotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
            
                // Workaround for a bug in PDFKit - remove the annotation before you add it
                self.currentPDFPage.removeAnnotation(currentAnnotation)
                
                // Eraser
                if self.inkType == .eraser {
                    self.erase(rect: rect, pointInPage: convertedPoint, currentUIViewPath: self.viewPath)
                    self.drawErasedAnnotation() // This function sets an annotation path split by the eraser as new PDF annotation, replacing the original one
                    
                    self.viewPath.removeAllPoints()
                    
                    // Alert the delegate that drawing has ended
                    self.freedrawDelegate?.freedrawStateChanged(isDrawing: false)

                } else {
                    
                    // Check if we created a circle. If we did, and the class variable for this is true, get a revised path. The default ovalIn UIBezierPath init creates a closed path, which cannot be split by other paths
                    if self.convertClosedCurvesToOvals, self.signingPath.resemblesOval(strokeWidth: self.width), self.inkType != .eraser {
                        let rectForOval = CGRect(x: rect.minX+self.width/2, y: rect.minY+self.width/2, width: rect.width-self.width, height: rect.height-self.width)
                        self.signingPath = UIBezierPath(openOvalIn: rectForOval)
                    }
                    
                    // Create the annotation we will save
                    self.annotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
                    let b = PDFBorder()
                    if self.inkType != .eraser {
                        b.lineWidth = self.width
                    } else {
                        b.lineWidth = 1
                    }
                    self.annotation.border = b
                    var alphaComponent : CGFloat = 1.0
                    if self.inkType == .highlighter {
                        alphaComponent = self.highlighterAlphaComponent
                    }
                    self.annotation.color = self.color.withAlphaComponent(alphaComponent)
                    // Move the annotation path to the center of its rect, because a path in a PDF annotation must be relative to the annotation's rect and not to the screen or page
                    _ = self.signingPath.moveCenter(to: rect.center)
                    self.annotation.add(self.signingPath)
                    // Record the annotation type in a convenient metadata field
                    self.annotation.userName = "\(self.inkType)"
                    self.currentPDFPage.addAnnotation(self.annotation)
                    // Add the annotation to the undo manager
                    self.registerUndo(annotations: [self.annotation])
                    // Store the annotation's path in its metadata dictionary if it includes curved (iOS bug)
                    if self.storeCurvedAnnotationPathsInMetadata {
                        self.annotation.setCurvedPathInContents()
                    }
                    
                    // Remove the UIView for the CAShapeLayer
                    self.removeDrawVeil()
                    self.viewPath.removeAllPoints()
                    // Alert the delegate that drawing has ended
                    self.freedrawDelegate?.freedrawStateChanged(isDrawing: false)
                }
            }
        } else {
            // Alert the delegate that drawing has ended
            freedrawDelegate?.freedrawStateChanged(isDrawing: false)
        }
    }
    
    // MARK: Touches Cancelled
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        // Alert the delegate that drawing has ended
        freedrawDelegate?.freedrawStateChanged(isDrawing: false)
        self.viewPath.removeAllPoints()
        self.signingPath.removeAllPoints()
        self.removeDrawVeil()
    }
    
    // MARK: Undo Manager
    
    // Function that registers the last annotation action in the undo history
    // Usually only one annotation is recorded in the internal array. Two are recorded only when erasing an annotation by splitting its path - the original one and the split-path one.
    private func registerUndo(annotations: [PDFAnnotation?]?) {
        guard annotations != nil else { return }
        guard currentPDFPage.pageRef != nil else { return }
        let pageNum = currentPDFPage.pageRef!.pageNumber
        if !annotationsToUndo.keys.contains(pageNum) {
            annotationsToUndo[pageNum] = []
        }
        annotationsToUndo[pageNum]?.append(annotations!)
        
        // Keep the number of entries to the limit set by the user, unless it is 0
        if annotationsToUndo[pageNum]?.count ?? 0 > maxUndoNumber && maxUndoNumber != 0 {
            annotationsToUndo[pageNum]?.removeFirst()
        }
        // Update the delegate so it can adjust the button states
        updateUndoRedoState()
    }
    
    /// Registers any PDFAnnotation in the PDFFreedrawGestureRecognizer undo manager for the current page. NB: Ink annotations created by PDFFreedrawGestureRecognizer are registered automatically.
    public func registerInAnnotationUndoManager(annotation: PDFAnnotation) {
        registerUndo(annotations: [annotation])
    }
    
    /// Function that checks the state of the `PDFFreedrawGestureRecognizer` undo and redo histories, and alerts the delegate accordingly
    public func updateUndoRedoState() {
        guard getCurrentPage() else { return }
        guard currentPDFPage.pageRef != nil else { return }
        let pageNum = currentPDFPage.pageRef!.pageNumber
        if annotationsToUndo[pageNum]?.count ?? 0 > 0 {
            if canUndo == false {
                canUndo = true
                // The state changed. alert the delegate
                freedrawDelegate?.freedrawUndoStateChanged()
            }
        } else {
            if canUndo == true {
                canUndo = false
                // The state changed. alert the delegate
                freedrawDelegate?.freedrawUndoStateChanged()
            }
        }
        if annotationsToRedo[pageNum]?.count ?? 0 > 0 {
            if canRedo == false {
                canRedo = true
                // The state changed. alert the delegate
                freedrawDelegate?.freedrawUndoStateChanged()
            }
        } else {
            if canRedo == true {
                canRedo = false
                // The state changed. alert the delegate
                freedrawDelegate?.freedrawUndoStateChanged()
            }
        }
    }
    
    /// Undo annotations by order of creation, up to the number set by `maxUndoNumber`
    public func undoAnnotation() {
        guard currentPDFPage.pageRef != nil else { return }
        let pageNum = currentPDFPage.pageRef!.pageNumber
        let lastAnnotation = annotationsToUndo[pageNum]?.popLast()
        guard lastAnnotation != nil else { return }
        DispatchQueue.main.async {
            if lastAnnotation!.last! != nil { // nil will be the case when eraser deleted a whole annotation and did not replace it with a split-path one.
                self.currentPDFPage.removeAnnotation(lastAnnotation!.last!!)
            }
            // If this annotation entry is double, then it was created by the eraser, and the original was also recorded and should be restored
            if lastAnnotation!.count == 2 {
                self.currentPDFPage.addAnnotation(lastAnnotation!.first!!)
            }
        }
        if !annotationsToRedo.keys.contains(pageNum) {
            annotationsToRedo[pageNum] = []
        }
        annotationsToRedo[pageNum]?.append(lastAnnotation!)
        updateUndoRedoState()
    }
    
    /// Redo annotations by reverse order of undoing
    public func redoAnnotation() {
        guard currentPDFPage.pageRef != nil else { return }
        let pageNum = currentPDFPage.pageRef!.pageNumber
        let lastAnnotation = annotationsToRedo[pageNum]?.popLast()
        guard lastAnnotation != nil else { return }
        DispatchQueue.main.async {
            // If this annotation entry is double, then it was created by the eraser, and the original was restored by the undo function and should now be removed
            if lastAnnotation!.count == 2 {
                self.currentPDFPage.removeAnnotation(lastAnnotation!.first!!)
            }
            if lastAnnotation!.last! != nil { // nil will be the case when eraser deleted a whole annotation and did not replace it with a split-path one.
                self.currentPDFPage.addAnnotation(lastAnnotation!.last!!)
            }
        }
        if !annotationsToUndo.keys.contains(pageNum) {
            annotationsToUndo[pageNum] = []
        }
        annotationsToUndo[pageNum]!.append(lastAnnotation!)
        updateUndoRedoState()
    }
    
    /// Reset annotation undo and redo history
    public func resetAnnotationUndoRedoHistory() {
        annotationsToUndo.removeAll()
        annotationsToRedo.removeAll()
        updateUndoRedoState()
    }
    
    // MARK: Eraser
    
    private func erase(rect: CGRect, pointInPage: CGPoint, currentUIViewPath: UIBezierPath) {
        
        // Get all of the page's annotations
        let annotations = currentPDFPage.annotations
        guard annotations.count > 0 else { return }
        
        // Loop through each of the page's annotations
        for annotation in annotations {
            // Initial test - intersection of the frames of the annotation and the current path, which is a very cheap test. Continue only if true.
            guard annotation.bounds.intersects(rect) else { continue }
            
            // For ink annotations - test a specific hit test for the point of intersection. More expensive. Non-ink annotations do not have paths to check against.
            if annotation.type == "Ink" {
                guard annotation.hitTest(pdfView: pdfView, pointInPage: pointInPage) ?? false else { continue }
            }
            
            // Deal with non-ink annotations by erasing them immediately, if eraseInkBySplittingPaths is false
            if annotation.type != "Ink" || !eraseInkBySplittingPaths {
                // Remove the annotation
                currentPDFPage.removeAnnotation(annotation)
                // Deal with the undo manager - since this is deletion, we need a double entry here (see the undo manager implementation above). Since no new annotation replaced the old one (as it does happen in the case of splitting UIBezierPaths), the second entry has to be nil.
                var annotationsForUndo : [PDFAnnotation?] = []
                annotationsForUndo.append(annotation)
                annotationsForUndo.append(nil)
                registerUndo(annotations: annotationsForUndo)
                continue
            }
            
            // Check if our class annotation variable is non-nil, different than the one we are currently looping through, and that we already have a path for an annotation that is being erased. If these conditions are met, then we have already drawn a split UIBezierPath on a CAShapeLayer for the annotation recorded by the class variable (see below), and we are now touching a new annotation on the page. We now have to split the PDF annotation path of the previous annotation (recorded by the class variable) on the PDF page, and remove its intersection with the eraser. This is also necessary if we just lifted our finger, but that case is dealt with in a separate function (drawErasedAnnotation()), because of our need to keep this phase and the following one in the same DispatchQueue block for synchronization purposes.
            DispatchQueue.main.async {

                if self.annotation != nil && self.annotation != annotation && !self.annotationBeingErasedPath.isEmpty {
                    
                    // Restart the UIView path, to prevent long, curved intersecting eraser paths from clearing off whole chunks of the annotation. Putting this in another DispatchQueue block prevents flicker.
                    DispatchQueue.main.async {
                        let lastPathPoint = self.viewPath.lastPoint()
                        self.viewPath.removeAllPoints()
                        self.viewPath.move(to: lastPathPoint)
                    }
                    
                    var annotationsForUndo : [PDFAnnotation] = [] // Prepare an array for the undo manager
                    var replacementAnnotation : PDFAnnotation? // Prepare the new, split-path annotation
                    
                    // Create a new instance of the intersected annotation path that was already used by the CAShapeLayer (see below). Invert it so it matches the PDF page coordinate system, and move it to its own rect center because paths within annotation rects should be relative to their own bounds, and not to the page. This also saves a lot of transposition calculation when moving from UIView coordinates to PDF page ones.
                    let erasedPath = self.erasedAnnotationPath.copy() as! UIBezierPath
                    if !erasedPath.isEmpty { // Necessary precaution
                        erasedPath.apply(CGAffineTransform(scaleX: 1/self.pdfView.scaleFactor, y: -1/self.pdfView.scaleFactor))
                        
                        // Make sure the userName metadata field of the annotation records the same freedraw ink type as the original annotation
                        var inkTypeToRecord : FreedrawType = .pen
                        switch self.annotation.userName {
                        case "highlighter":
                            inkTypeToRecord = .highlighter
                        default:
                            inkTypeToRecord = .pen
                        }
                        
                        // Get the bounds for the new annotation, taking into account the stroke width
                        let replacementAnnotationBounds = self.pdfView.convert(CGRect(x: self.erasedAnnotationPath.bounds.minX-self.width/2, y: self.erasedAnnotationPath.bounds.minY-self.width/2, width: self.erasedAnnotationPath.bounds.width+self.width, height: self.erasedAnnotationPath.bounds.height+self.width), to: self.currentPDFPage)
                        
                        // Move the path to the center of the bounds
                        _ = erasedPath.moveCenter(to: replacementAnnotationBounds.center)
                        
                        // Populate the replacement annotation
                        replacementAnnotation = PDFAnnotation(bounds: replacementAnnotationBounds, forType: .ink, withProperties: nil)
                        replacementAnnotation?.add(erasedPath)
                        replacementAnnotation?.border = self.annotation.border
                        replacementAnnotation?.color = self.originalAnnotationColor
                        replacementAnnotation?.userName = "\(inkTypeToRecord)"
                    }
                    
                    // Remove the original annotation from the page
                    self.currentPDFPage.removeAnnotation(self.annotation)
                    
                    // If the replacement annotation is valid, add it to the page
                    if !erasedPath.isEmpty && replacementAnnotation != nil {
                        self.currentPDFPage.addAnnotation(replacementAnnotation!)
                        replacementAnnotation?.setCurvedPathInContents()
                    }
                    
                    if !erasedPath.isEmpty { // Must continue the same condition from before
                        // Restore the original annotation color and append the annotation to the undo manager array. The annotation was made transparent before, when we started erasing it on a CAShapeLayer (see below).
                        self.annotation.color = self.originalAnnotationColor
                        // Replace the path because of the iOS bug
                        if let replacementPath = self.annotation.getAnnotationPath(), let pathToRemove = self.annotation.paths?.first {
                            self.annotation.remove(pathToRemove)
                            self.annotation.add(replacementPath)
                        }
                        annotationsForUndo.append(self.annotation)
                        
                        // Add the replacement annotation to the undo manager array and push both original and replacement to the undo manager
                        if let replacementAnnotationUnwrapped = replacementAnnotation {
                            annotationsForUndo.append(replacementAnnotationUnwrapped)
                            self.registerUndo(annotations: annotationsForUndo)
                        }
                    }
                    
                    // Clear the paths of both the original annotation and the replacement annotation
                    self.annotationBeingErasedPath.removeAllPoints()
                    self.erasedAnnotationPath.removeAllPoints()
                        
                    // Remove the CAShapeLayer that was drawn before (see below)
                    if self.drawVeil.layer.sublayers != nil {
                        for layer in self.drawVeil.layer.sublayers! {
                            layer.removeFromSuperlayer()
                        }
                    }
                }
            
                // If we got here, this means we have already saved any previously-dealt-with erased annotations to the PDF page, and it is time to start erasing a new one.
                // First, if this is the first time we are encountering this annotation (its recorded path is empty), let's translate its path to the UIView coordinates.
                if self.annotationBeingErasedPath.isEmpty {
                    
                    // Read the original annotation path, unwrap it, assign it to the class variable
                    if let annotationPathUnwrapped = annotation.getAnnotationPath() {
                        self.annotationBeingErasedPath = annotationPathUnwrapped.copy() as! UIBezierPath
                        // Get annotation rect origin, converted to UIView coordinates
                        let origin = self.pdfView.superview!.convert(annotation.bounds.origin, from: self.pdfView)
                        // Get the PDF page bounds, converted to UIView coordinates
                        let pdfPageBounds = self.pdfView.convert(self.currentPDFPage.bounds(for: .cropBox), from: self.currentPDFPage)
                        // Apply transformations to the annotation path from PDF annotation coordinates to UIView coordinates, taking into account the view's scale factor
                        self.annotationBeingErasedPath.apply(CGAffineTransform(scaleX: self.pdfView.scaleFactor, y: -self.pdfView.scaleFactor))
                        self.annotationBeingErasedPath.apply(CGAffineTransform(translationX: origin.x*self.pdfView.scaleFactor + pdfPageBounds.minX, y: self.pdfView.bounds.height - pdfPageBounds.minY - origin.y*self.pdfView.scaleFactor))
                        
                        // Set the class variable for the annotation, so we know to avoid setting this annotation to the PDF page until we start dealing with a different annotation
                        self.annotation = annotation
                        
                        // Record the annotation's color, because we are about to hide it for the duration of drawing on the CAShapeLayer
                        self.originalAnnotationColor = annotation.color
                    }
                }
                
                // The previous block is only called once per annotation, while the current eraser path is updated every time this function is called. Let's get the difference between them. The Clipping Bezier library will handle that calculation.
            
                // Fatten the eraser and stroke its path, so that we can detect the intersection
                // Ideally, we'll determine the stroking width according to the line width of the original annotation, and take into account the fact that its stroke is rounded
                var strokingWidth = (self.annotation.border?.lineWidth ?? 0) * CGFloat.pi * self.eraserStrokeWidthFactor
                if strokingWidth == 0 { strokingWidth = 30 * self.eraserStrokeWidthFactor }
                let eraserPath = UIBezierPath(cgPath: currentUIViewPath.cgPath.copy(strokingWithWidth: strokingWidth, lineCap: .round, lineJoin: .round, miterLimit: 0))
                // Use Clipping Bezier to get the path difference between the annotation and the eraser
                let erasedAnnotationPaths = self.annotationBeingErasedPath.difference(with: eraserPath)
                
                // There is only one path resulting from the previous calculation, but better safe than sorry
                for i in 0..<(erasedAnnotationPaths?.count ?? 0) {
                    // Clear the erasedAnnotationPath and repopulate it - only if there is something to repopulate it with. Otherwise the last viable path is maintained for creating the finalized PDF annotation.
                    self.erasedAnnotationPath.removeAllPoints()
                    self.erasedAnnotationPath = erasedAnnotationPaths![i]
                    
                    // Draw temporary annotation on screen using a CAShapeLayer, to be replaced later with the PDFAnnotation
                    // First, clear any existing sublayers
                    if self.drawVeil.layer.sublayers != nil {
                        for layer in self.drawVeil.layer.sublayers! {
                            layer.removeFromSuperlayer()
                        }
                    }
                    
                    // Time to draw
                    let viewPathLayer = CAShapeLayer()
                    viewPathLayer.strokeColor = self.originalAnnotationColor.cgColor
                    viewPathLayer.lineWidth = CGFloat((self.annotation.border?.lineWidth ?? self.width) * self.pdfView.scaleFactor)
                    viewPathLayer.path = self.erasedAnnotationPath.cgPath
                    viewPathLayer.fillColor = UIColor.clear.cgColor
                    viewPathLayer.lineJoin = CAShapeLayerLineJoin.round
                    viewPathLayer.lineCap = CAShapeLayerLineCap.round

                    self.drawVeil.layer.addSublayer(viewPathLayer)
                }

                // Hide the original annotation if it is not already hidden
                if self.annotation.color != UIColor.clear {
                    self.annotation.color = UIColor.clear
                }
            }
        }
    }
    
    // The following function duplicates the block from the above function that deals with recording the newly split-pathed annotation on the PDF page. The current function is called from touchesEnded, whereas the similar block in the previous function is called when the eraser is encountering a new annotation on the page. The main reason for seperating these two similar blocks is the timing of the Dispatch Queues.
    // For more detailed comments, please consult the block in the function above.
    private func drawErasedAnnotation() {
        // Prevent immediate deletion of annotations when eraser is swiping too quickly
        guard !self.erasedAnnotationPath.isEmpty else { return }
        
        DispatchQueue.main.async {
            var annotationsForUndo : [PDFAnnotation] = []
            var replacementAnnotation : PDFAnnotation?
            let erasedPath = self.erasedAnnotationPath.copy() as! UIBezierPath
            if !erasedPath.isEmpty {
                erasedPath.apply(CGAffineTransform(scaleX: 1/self.pdfView.scaleFactor, y: -1/self.pdfView.scaleFactor))
            
                var inkTypeToRecord : FreedrawType = .pen
                switch self.annotation.userName {
                case "highlighter":
                    inkTypeToRecord = .highlighter
                default:
                    inkTypeToRecord = .pen
                }
                
                // Get the bounds for the new annotation, taking into account the stroke width
                let replacementAnnotationBounds = self.pdfView.convert(CGRect(x: self.erasedAnnotationPath.bounds.minX-self.width/2, y: self.erasedAnnotationPath.bounds.minY-self.width/2, width: self.erasedAnnotationPath.bounds.width+self.width, height: self.erasedAnnotationPath.bounds.height+self.width), to: self.currentPDFPage)
                
                // Move the path to the center of the bounds
                _ = erasedPath.moveCenter(to: replacementAnnotationBounds.center)
                
                // Populate the replacement annotation
                replacementAnnotation = PDFAnnotation(bounds: replacementAnnotationBounds, forType: .ink, withProperties: nil)
                replacementAnnotation?.add(erasedPath)
                replacementAnnotation?.border = self.annotation.border
                replacementAnnotation?.color = self.originalAnnotationColor
                replacementAnnotation?.userName = "\(inkTypeToRecord)"
                
                // Remove the original annotation from the page
                self.currentPDFPage.removeAnnotation(self.annotation)
                
                // Add the replacement annotation to the page
                if !erasedPath.isEmpty && replacementAnnotation != nil {
                    self.currentPDFPage.addAnnotation(replacementAnnotation!)
                    replacementAnnotation?.setCurvedPathInContents()
                }
                
                // Restore the original annotation color and append the annotation to the undo manager
                self.annotation.color = self.originalAnnotationColor
                // Replace the path because of the iOS bug
                if let replacementPath = self.annotation.getAnnotationPath(), let pathToRemove = self.annotation.paths?.first {
                    self.annotation.remove(pathToRemove)
                    self.annotation.add(replacementPath)
                }
                annotationsForUndo.append(self.annotation)
                
                // Append the replacement annotation to the undo manager
                if let replacementAnnotationUnwrapped = replacementAnnotation {
                    annotationsForUndo.append(replacementAnnotationUnwrapped)
                    self.registerUndo(annotations: annotationsForUndo)
                }
                
                
            } else {
                // This should not be reached - just a safety measure to restore last viable annotation
                self.annotation.color = self.originalAnnotationColor
            }
            
            // Clear the paths of both the original annotation and the replacement annotation
            self.annotationBeingErasedPath.removeAllPoints()
            self.erasedAnnotationPath.removeAllPoints()
                
            // Remove the CAShapeLayer
            if self.drawVeil.layer.sublayers != nil {
                for layer in self.drawVeil.layer.sublayers! {
                    layer.removeFromSuperlayer()
                }
            }
        }
    }
    
    // MARK: Helper Functions
    
    // Function that removes the drawVeil
    private func removeDrawVeil() {
        DispatchQueue.main.async {
            for drawVeilSubview in self.pdfView.superview!.subviews.filter({$0.tag==35791}) {
                drawVeilSubview.removeFromSuperview()
            }
        }
    }
}
