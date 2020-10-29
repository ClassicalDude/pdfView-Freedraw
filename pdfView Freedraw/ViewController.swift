//
//  ViewController.swift
//  pdfView Freedraw
//
//  Created by Ron Regev on 02/10/2020.
//

import UIKit
import PDFKit

class ViewController: UIViewController, UIGestureRecognizerDelegate, PDFFreedrawGestureRecognizerUndoDelegate {
    
    // Button outlets
    @IBOutlet weak var blueLineOutlet: UIButton!
    @IBOutlet weak var redHighlightOutlet: UIButton!
    @IBOutlet weak var eraserOutlet: UIButton!
    @IBOutlet weak var perfectOvalsOutlet: UIButton!
    @IBOutlet weak var undoOutlet: UIButton!
    @IBOutlet weak var redoOutlet: UIButton!
    
    // The gesture recognizer class for drawing ink PDF annotations and erasing all annotations
    var pdfFreedraw : PDFFreedrawGestureRecognizer!
    
    // MARK: View Controller Functions
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        // Set up the buttons
        redHighlightOutlet.tintColor = UIColor.red
        eraserOutlet.tintColor = UIColor.systemGreen
        perfectOvalsOutlet.tintColor = UIColor.darkGray
        undoOutlet.setTitleColor(UIColor.lightGray, for: .disabled)
        redoOutlet.setTitleColor(UIColor.lightGray, for: .disabled)
        perfectOvalsOutlet.setTitleColor(UIColor.lightGray, for: .disabled)
        
        // Prepare the example PDF document and PDF view
        let pdfDocument = PDFDocument(url: Bundle.main.url(forResource: "blank", withExtension: "pdf")!)
        let pdfView = PDFView()
        
        // Layout: should be done on the main thread
        DispatchQueue.main.async {
            
            pdfView.frame = self.view.frame
            self.view.addSubview(pdfView)
            self.view.sendSubviewToBack(pdfView) // Allow the UIButtons to be on top
            
            // The following block adjusts the view and its contents in an optimal way for display and annotation
            // First - layout options necessary to ensure consistent results for all documents
            pdfView.displayMode = .singlePage
            pdfView.translatesAutoresizingMaskIntoConstraints = true
            pdfView.contentMode = .scaleAspectFit
            
            // A few additional options that can be useful
            //pdfView.displayDirection = .horizontal
            //pdfView.usePageViewController(false, withViewOptions: [:])
            //pdfView.autoresizesSubviews = true
            //pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight, .flexibleTopMargin, .flexibleLeftMargin]
            
            // From here - options that should probably be set, and by this order, including the repeats
            // This ensures the proper scaling of the PDF page
            pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.maxScaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.sizeToFit()
            pdfView.layoutDocumentView()
            pdfView.maxScaleFactor = 5.0
            
            // Deal with the page shadows that appear by default
            if #available(iOS 12.0, *) {
                pdfView.pageShadowsEnabled = false
            } else {
                pdfView.layer.borderWidth = 15 // iOS 11: hide the d*** shadow
                pdfView.layer.borderColor = UIColor.white.cgColor
            }
            
            // For iOS 11-12, the document should be loaded only after the view is in the stack. If this is called outside the DispatchQueue block, it may be executed too early
            pdfView.document = pdfDocument
            // autoScales must be set to true, otherwise the swipe motion will drag the canvas instead of drawing. This should be done AFTER loading the document.
            pdfView.autoScales = true
        }
        
        // Define the gesture recognizer. You can use a default initializer for a narrow red pen
        pdfFreedraw = PDFFreedrawGestureRecognizer(color: UIColor.blue, width: 3, type: .pen)
        pdfFreedraw.delegate = self // This is for the UIGestureRecognizer delegate
        pdfFreedraw.undoDelegate = self // This is for undo history notifications, to inform button states
        pdfFreedraw.isEnabled = true // Not necessary by default. The simplest way to turn drawing on and off.
        
        // Set the allowed number of undo actions. The default is 10
        // Choosing the number 0 will take that limit off, for as long as the class instance is allocated
        pdfFreedraw.maxUndoNumber = 5
        
        // Choose whether ink annotations will be erased as a whole, or by splitting their UIBezierPaths. The second option provides a more intuitive UX, but may have unpredictable results at times.
        pdfFreedraw.eraseInkBySplittingPaths = true
        
        // Choose a factor for the stroke width of the eraser. The default is 1.
        pdfFreedraw.eraserStrokeWidthFactor = 1.0
        
        // Choose the alpha component of the highlighter type of the ink annotation
        pdfFreedraw.highlighterAlphaComponent = 0.3
        
        // Set the pdfView's isUserInteractionEnabled property to false, otherwise you'll end up swiping pages instead of drawing. This is also one of the conditions used by the PDFFreeDrawGestureRecognizer to take over the touches recognition.
        pdfView.isUserInteractionEnabled = false
        
        // Add the gesture recognizer to the *superview* of the PDF view - another condition
        view.addGestureRecognizer(pdfFreedraw)
        
        /* IMPORTANT!
        You must make sure all other gesture recognizers have their cancelsTouchesInView option set to false, otherwise different stages of this gesture recognizer's touches may not be called, and the CAShapeLayer that holds the temporary annotation will not be removed.
         */
        
        // Set the initial state of the undo and redo buttons (see functions below)
        freedrawUndoStateChanged()
        updateButtonsState()
    }
    
    // This function makes sure you can control gestures aimed at UIButtons
    // NB: This does not work on Mac Catalyst - seems to be a bug in Catalyst
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle button taps
        return !(touch.view is UIButton)
    }
    
    // This function allows for multiple gesture recognizers to coexist
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
        -> Bool {
            if gestureRecognizer is PDFFreedrawGestureRecognizer {
            return true
        }
        return false
    }
    
    // MARK: Button States
    
    // This is the protocol stub of PDFFreedrawGestureRecognizerUndoDelegate, which is triggered whenever there is a change in canUndo or canRedo properties of the PDFFreedrawGestureRecognizer class
    func freedrawUndoStateChanged() {
        if pdfFreedraw.canUndo {
            undoOutlet.isEnabled = true
        } else {
            undoOutlet.isEnabled = false
        }
        if pdfFreedraw.canRedo {
            redoOutlet.isEnabled = true
        } else {
            redoOutlet.isEnabled = false
        }
    }
    
    func updateButtonsState() {
        switch pdfFreedraw.inkType {
        case .highlighter:
            blueLineOutlet.isSelected = false
            redHighlightOutlet.isSelected = true
            eraserOutlet.isSelected = false
            if pdfFreedraw.convertClosedCurvesToOvals {
                perfectOvalsOutlet.isSelected = true
            } else {
                perfectOvalsOutlet.isSelected = false
            }
            perfectOvalsOutlet.isEnabled = true
            
        case .eraser:
            blueLineOutlet.isSelected = false
            redHighlightOutlet.isSelected = false
            eraserOutlet.isSelected = true
            perfectOvalsOutlet.isSelected = false
            perfectOvalsOutlet.isEnabled = false
            
        default: // .pen
            blueLineOutlet.isSelected = true
            redHighlightOutlet.isSelected = false
            eraserOutlet.isSelected = false
            if pdfFreedraw.convertClosedCurvesToOvals {
                perfectOvalsOutlet.isSelected = true
            } else {
                perfectOvalsOutlet.isSelected = false
            }
            perfectOvalsOutlet.isEnabled = true
        }
    }

    // MARK: Button Actions
    
    @IBAction func blueLineAction(_ sender: UIButton) {
        pdfFreedraw.color = UIColor.blue
        pdfFreedraw.width = 3
        pdfFreedraw.inkType = .pen
        updateButtonsState()
    }
    
    @IBAction func redHighlightAction(_ sender: UIButton) {
        pdfFreedraw.color = UIColor.red
        pdfFreedraw.width = 20
        pdfFreedraw.inkType = .highlighter
        updateButtonsState()
    }
    
    @IBAction func eraserAction(_ sender: UIButton) {
        pdfFreedraw.inkType = .eraser
        updateButtonsState()
    }
    
    @IBAction func undoAction(_ sender: UIButton) {
        pdfFreedraw.undoAnnotation()
    }
    
    @IBAction func redoAction(_ sender: UIButton) {
        pdfFreedraw.redoAnnotation()
    }
    
    @IBAction func drawPerfectOvals(_ sender: UIButton) {
        pdfFreedraw.convertClosedCurvesToOvals = !pdfFreedraw.convertClosedCurvesToOvals
        updateButtonsState()
    }
}

