//
//  ViewController.swift
//  pdfView Freedraw
//
//  Created by Ron Regev on 02/10/2020.
//

import UIKit
import PDFKit

class ViewController: UIViewController, UIGestureRecognizerDelegate, PDFFreedrawGestureRecognizerUndoDelegate {
    
    @IBOutlet weak var blueLineOutlet: UIButton!
    @IBOutlet weak var redHighlightOutlet: UIButton!
    @IBOutlet weak var eraserOutlet: UIButton!
    @IBOutlet weak var perfectOvalsOutlet: UIButton!
    @IBOutlet weak var undoOutlet: UIButton!
    @IBOutlet weak var redoOutlet: UIButton!
    
    var pdfFreedraw : PDFFreedrawGestureRecognizer!
    
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
        DispatchQueue.main.async { // Layout should be done on the main thread
            
            pdfView.frame = self.view.frame
            self.view.addSubview(pdfView)
            self.view.sendSubviewToBack(pdfView) // Allow the UIButtons to be on top
            
            // The following block adjusts the view and its contents in an optimal way for display and annotation
            
            // First - a few useful options, now commented out
//            pdfView.displayMode = .singlePage
//            pdfView.displayDirection = .horizontal
//            pdfView.usePageViewController(false, withViewOptions: [:])
//            pdfView.translatesAutoresizingMaskIntoConstraints = true
//            pdfView.contentMode = .scaleAspectFit
            
            // From here - options that should probably be set, and by this order, including the repeats
            // This ensures the proper scaling of the PDF page
            pdfView.autoresizesSubviews = true
            pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight, .flexibleTopMargin, .flexibleLeftMargin]
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
        
        // Set the allowed number of undo actions
        // Choosing the number 0 will take off that limit, for as long as the class instance is allocated
        pdfFreedraw.maxUndoNumber = 5
        
        // Choose whether ink annotations will be erased as a whole, or by splitting their UIBezierPaths. The second option provides a more intuitive UX, but may have unpredictable results at times.
        pdfFreedraw.eraseInkBySplittingPaths = true
        
        // Set the pdfView's isUserInteractionEnabled property to false, otherwise you'll end up swiping pages instead of drawing. This is also one of the conditions used by the PDFFreeDrawGestureRecognizer to execute, so you can use it to turn free drawing on and off.
        pdfView.isUserInteractionEnabled = false
        
        // Add the gesture recognizer to the superview of the PDF view
        view.addGestureRecognizer(pdfFreedraw)
        
        /* IMPORTANT!
        You must make sure all other gesture recognizers have their cancelsTouchesInView option set to false, otherwise different stages of this gesture recognizer's touches may not be called, and the CAShapeLayer that holds the temporary annotation will not be removed.
         */
        
        // Set the initial state of the undo and redo buttons
        freedrawUndoStateChanged()
        updateButtonsState()
    }
    
    // This function will make sure you can control gestures aimed at UIButtons
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle button taps
        return !(touch.view is UIButton)
    }
    
    // This function will allow for multiple gesture recognizers to coexist
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
        -> Bool {
            if gestureRecognizer is PDFFreedrawGestureRecognizer {
            return true
        }
        return false
    }
    
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

