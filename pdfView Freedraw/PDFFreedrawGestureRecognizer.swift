//
//  PDFFreedrawGestureRecognizer.swift
//  pdfView Freedraw
//
//  Created by Ron Regev on 02/10/2020.
//

import UIKit
import PDFKit

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
    public static var type : FreedrawType = .pen
    
    private var drawVeil = UIView() // will be used for temporary CAShapeLayer
    private var startLocation : CGPoint?
    private var movedTest : CGPoint?
    private var totalDistance : CGFloat = 0
    private var signingPath = UIBezierPath()
    private var viewPath = UIBezierPath()
    private var pdfView : PDFView?
    private var currentAnnotation : PDFAnnotation?
    
    convenience init(color: UIColor?, width: CGFloat?, type: FreedrawType?) {
        PDFFreedrawGestureRecognizer.color = color ?? UIColor.red
        PDFFreedrawGestureRecognizer.width = width ?? 3
        PDFFreedrawGestureRecognizer.type = type ?? .pen
        self.init()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        // Get the PDFView to annotate
        let possiblePDFViews = self.view?.subviews.filter({$0 is PDFView})
        if (possiblePDFViews?.count ?? 0) > 0 {
            for possiblePDFView in possiblePDFViews! {
                if possiblePDFView is PDFView {
                    pdfView = possiblePDFView as? PDFView
                }
            }
        }
        if pdfView == nil {
            print ("PDFFreedrawGestureRecognizer must be attached to a superview of a PDFView")
            return
        }
        if pdfView!.isUserInteractionEnabled {
            return
        }
        
        if let touch = touches.first {
            
            // Attach the UIView that we will use to draw the annotation on a CALayer, until the touches end
            drawVeil = UIView(frame: pdfView!.frame)
            drawVeil.tag = 35791 // For identifying and removing all instances later on
            drawVeil.isUserInteractionEnabled = false
            DispatchQueue.main.async {
                self.pdfView?.superview?.addSubview(self.drawVeil)
//                self.pdfView?.superview?.sendSubviewToBack(self.drawVeil)
//                self.pdfView?.superview?.sendSubviewToBack(self.pdfView!)
                
                // movedTest will be used in touchedEnded to ascertain if we moved, or just tapped
                self.movedTest = touch.location(in: self.view)
                
                // startLocation will be used for adding to the UIBezierPath
                self.startLocation = touch.location(in: self.pdfView)
                guard (self.startLocation != nil) else { return }
                self.totalDistance = 0

                self.signingPath = UIBezierPath()
                self.signingPath.move(to: self.pdfView!.convert(self.startLocation!, to: self.pdfView!.page(for: self.startLocation!, nearest: true)!))
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if pdfView == nil || pdfView!.isUserInteractionEnabled{
            return
        }
        if let touch = touches.first, let startLocation = startLocation {
            DispatchQueue.main.async {
                
                // Test for minimal viable distance to register the move
                let currentLocation = touch.location(in: self.pdfView)
                let dX = currentLocation.x - startLocation.x
                let dY = currentLocation.y - startLocation.y
                self.totalDistance += sqrt(pow(dX, 2) + pow(dY, 2))
                if self.totalDistance < 10.0 { // change the "10.0" to your value of choice if you wish to change the minimal viable distance
                    return
                }
                
                // Get the current gesture location
                let position = touch.location(in: self.pdfView)
                let convertedPoint = self.pdfView!.convert(position, to: self.pdfView!.page(for: position, nearest: true)!)
                // Add line to the PDF annotation UIBezierPath
                self.signingPath.addLine(to: convertedPoint) // For the PDFAnnotation
                
                // Create a UIBezierPath and a line for the CAShapeLayer we will use during this phase of the touches
                self.viewPath.move(to: self.startLocation!) // For the CAShapeLayer
                self.viewPath.addLine(to: currentLocation)
                if self.signingPath.isEmpty == false { // Prevent crashes with very short gestures
                    var rect = CGRect()
                    if PDFFreedrawGestureRecognizer.type != .eraser {
                        // Change the rect to allow for lines wider than a point. Not needed for the eraser.
                        rect = CGRect(x:self.signingPath.bounds.minX-PDFFreedrawGestureRecognizer.width/2, y:self.signingPath.bounds.minY-PDFFreedrawGestureRecognizer.width/2, width:self.signingPath.bounds.maxX-self.signingPath.bounds.minX+PDFFreedrawGestureRecognizer.width, height:self.signingPath.bounds.maxY-self.signingPath.bounds.minY+PDFFreedrawGestureRecognizer.width)
                    } else {
                        rect = self.signingPath.bounds
                    }
                    
                    // Erase annotation if in eraser mode
                    if PDFFreedrawGestureRecognizer.type == .eraser {
                        let annotations = self.pdfView?.currentPage?.annotations
                        for annotation in annotations! {
                            if annotation.bounds.intersects(rect) {
                                self.pdfView?.currentPage?.removeAnnotation(annotation)
                            }
                        }
                        
                    } else {
                        
                        // Clear the remaining CAShapeLayer from the drawVeil
                        self.drawVeil.layer.sublayers?[0].removeFromSuperlayer()
                        
                        var alphaComponent : CGFloat = 1.0
                        if PDFFreedrawGestureRecognizer.type == .highlighter {
                            alphaComponent = 0.3
                        }
                        
                        // Draw temporary annotation on screen using a CAShapeLayer, to be replaced later with the PDFAnnotation
                        let viewPathLayer = CAShapeLayer()
                        viewPathLayer.strokeColor = PDFFreedrawGestureRecognizer.color.withAlphaComponent(alphaComponent).cgColor
                        viewPathLayer.lineWidth = CGFloat(PDFFreedrawGestureRecognizer.width * self.pdfView!.scaleFactor)
                        viewPathLayer.path = self.viewPath.cgPath
                        viewPathLayer.fillColor = UIColor.clear.cgColor
                        viewPathLayer.lineJoin = CAShapeLayerLineJoin.round
                        viewPathLayer.lineCap = CAShapeLayerLineCap.round

                        self.drawVeil.layer.addSublayer(viewPathLayer)
                        
                        // Update the startLocation for touchesEnded below
                        self.startLocation = currentLocation
                    }
                } else {
                    // Signing path was empty
                    DispatchQueue.main.async {
                        // Remove the UIView for the CAShapeLayer
                        for drawVeilSubview in self.pdfView!.superview!.subviews.filter({$0.tag==35791}) {
                            drawVeilSubview.removeFromSuperview()
                        }
                    }
                }
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if pdfView == nil || pdfView!.isUserInteractionEnabled {
            return
        }
        if let touch = touches.first {
            DispatchQueue.main.async {
                // Get the current gesture location
                let position = touch.location(in: self.pdfView)
                
                // Test if we indeed moved between touchesBegan and touchesEnded. If we did, apend the move to the UIBezierPath of the PDF annotation.
                if self.movedTest == touch.location(in: self.view) {
                    self.signingPath.removeAllPoints() // Prevent a short line when accessed from long tap
                } else {
                    self.signingPath.addLine(to: self.pdfView!.convert(position, to: self.pdfView!.page(for: position, nearest: true)!))
                }
                if self.signingPath.isEmpty == false { // Prevent crashes with very short gestures
                    var rect = CGRect()
                    if PDFFreedrawGestureRecognizer.type != .eraser {
                        // Change the rect to allow for lines wider than a point. Not needed for the eraser.
                        rect = CGRect(x:self.signingPath.bounds.minX-PDFFreedrawGestureRecognizer.width/2, y:self.signingPath.bounds.minY-PDFFreedrawGestureRecognizer.width/2, width:self.signingPath.bounds.maxX-self.signingPath.bounds.minX+PDFFreedrawGestureRecognizer.width, height:self.signingPath.bounds.maxY-self.signingPath.bounds.minY+PDFFreedrawGestureRecognizer.width)
                    } else {
                        rect = self.signingPath.bounds
                    }
                    
                    // Create the PDF annotation
                    self.currentAnnotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
                
                    // Workaround for a bug in PDFKit - remove the annotation before you add it
                    self.pdfView?.document?.page(at: (self.pdfView?.document?.index(for: (self.pdfView?.currentPage!)!))!)?.removeAnnotation(self.currentAnnotation!)
                    
                    // Eraser
                    if PDFFreedrawGestureRecognizer.type == .eraser {
                        let annotations = self.pdfView?.currentPage?.annotations
                        for annotation in annotations! {
                            if annotation.bounds.intersects(rect) {
                                self.pdfView?.currentPage?.removeAnnotation(annotation)
                            }
                        }
                        // Remove the UIView for the CAShapeLayer
                        for drawVeilSubview in self.pdfView!.superview!.subviews.filter({$0.tag==35791}) {
                            drawVeilSubview.removeFromSuperview()
                        }
                        self.viewPath.removeAllPoints()

                    } else {
                        
                        // Create the annotation we will save
                        let annotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
                        let b = PDFBorder()
                        if PDFFreedrawGestureRecognizer.type != .eraser {
                            b.lineWidth = PDFFreedrawGestureRecognizer.width
                        } else {
                            b.lineWidth = 1
                        }
                        annotation.border = b
                        var alphaComponent : CGFloat = 1.0
                        if PDFFreedrawGestureRecognizer.type == .highlighter {
                            alphaComponent = 0.3
                        }
                        annotation.color = PDFFreedrawGestureRecognizer.color.withAlphaComponent(alphaComponent)
                        _ = self.signingPath.moveCenter(to: rect.center)
                        annotation.add(self.signingPath)
                        self.pdfView?.document?.page(at: (self.pdfView?.document?.index(for: (self.pdfView?.currentPage!)!))!)?.addAnnotation(annotation)
                        
                        // Clear the drawVeil its UIBezierPath
                        // Remove the UIView for the CAShapeLayer
                        for drawVeilSubview in self.pdfView!.superview!.subviews.filter({$0.tag==35791}) {
                            drawVeilSubview.removeFromSuperview()
                        }
                        self.viewPath.removeAllPoints()
                    }
                } else {
                    // Signing path was empty
                    self.viewPath.removeAllPoints()
                    DispatchQueue.main.async {
                        // Remove the UIView for the CAShapeLayer
                        for drawVeilSubview in self.pdfView!.superview!.subviews.filter({$0.tag==35791}) {
                            drawVeilSubview.removeFromSuperview()
                        }
                    }
                }
            }
        }
    }
}
