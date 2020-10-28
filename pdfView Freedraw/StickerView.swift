//
//  StickerView.swift
//  StickerView
//
//  Copyright © All rights reserved.
//

import UIKit

public enum StickerViewHandler:Int {
		case close = 0
		case rotate
		case flip
		case resize
}

public enum StickerViewPosition:Int {
		case topLeft = 0
		case topRight
		case bottomLeft
		case bottomRight
}

@inline(__always) func CGRectGetCenter(_ rect:CGRect) -> CGPoint {
		return CGPoint(x: rect.midX, y: rect.midY)
}

@inline(__always) func CGRectScale(_ rect:CGRect, wScale:CGFloat, hScale:CGFloat) -> CGRect {
		return CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width * wScale, height: rect.size.height * hScale)
}

@inline(__always) func CGAffineTransformGetAngle(_ t:CGAffineTransform) -> CGFloat {
		return atan2(t.b, t.a)
}

@inline(__always) func CGPointGetDistance(point1:CGPoint, point2:CGPoint) -> CGFloat {
		let fx = point2.x - point1.x
		let fy = point2.y - point1.y
		return sqrt(fx * fx + fy * fy)
}

@objc public  protocol StickerViewDelegate {
		@objc func stickerViewDidBeginMoving(_ stickerView: StickerView)
		@objc func stickerViewDidChangeMoving(_ stickerView: StickerView)
		@objc func stickerViewDidEndMoving(_ stickerView: StickerView)
		@objc func stickerViewDidBeginRotating(_ stickerView: StickerView)
		@objc func stickerViewDidChangeRotating(_ stickerView: StickerView)
		@objc func stickerViewDidEndRotating(_ stickerView: StickerView)
		@objc func stickerViewDidBeginResizing(_ stickerView: StickerView)
		@objc func stickerViewDidChangeResizing(_ stickerView: StickerView)
		@objc func stickerViewDidEndResizing(_ stickerView: StickerView)
		@objc func stickerViewDidClose(_ stickerView: StickerView)
		@objc func stickerViewDidTap(_ stickerView: StickerView)
}

public class StickerView: UIView {
	
	public override var canBecomeFirstResponder: Bool {
			return true
	}
	
		public var delegate: StickerViewDelegate!
		/// The contentView inside the sticker view.
		public var contentView:UIView!
		/// Enable the close handler or not. Default value is YES.
		public var enableClose:Bool = true {
				didSet {
						if self.showEditingHandlers {
								self.setEnableClose(self.enableClose)
						}
				}
		}
		/// Enable the rotate/resize handler or not. Default value is YES.
		public var enableRotate:Bool = true{
				didSet {
						if self.showEditingHandlers {
								self.setEnableRotate(self.enableRotate)
						}
				}
		}
	
	public var enableResize:Bool = true{
			didSet {
					if self.showEditingHandlers {
							self.setEnableResize(self.enableResize)
					}
			}
	}
		/// Enable the flip handler or not. Default value is YES.
		public var enableFlip:Bool = true
		/// Show close and rotate/resize handlers or not. Default value is YES.
		public var showEditingHandlers:Bool = true {
				didSet {
						if self.showEditingHandlers {
								self.setEnableClose(self.enableClose)
								self.setEnableRotate(self.enableRotate)
								self.setEnableResize(self.enableResize)
								self.setEnableFlip(self.enableFlip)
								self.contentView?.layer.borderWidth = 1
						}
						else {
								self.setEnableClose(false)
								self.setEnableRotate(false)
								self.setEnableResize(false)
								self.setEnableFlip(false)
								self.contentView?.layer.borderWidth = 0
						}
				}
		}
		
		/// Minimum value for the shorter side while resizing. Default value will be used if not set.
		private var _minimumSize:NSInteger = 0
		public  var minimumSize:NSInteger {
				set {
						_minimumSize = max(newValue, self.defaultMinimumSize)
				}
				get {
						return _minimumSize
				}
		}
		/// Color of the outline border. Default: brown color.
		private var _outlineBorderColor:UIColor = .clear
		public  var outlineBorderColor:UIColor {
				set {
						_outlineBorderColor = newValue
						self.contentView?.layer.borderColor = _outlineBorderColor.cgColor
				}
				get {
						return _outlineBorderColor
				}
		}
		/// A convenient property for you to store extra information.
		public  var userInfo:Any?
		
		/**
		 *  Initialize a sticker view. This is the designated initializer.
		 *
		 *  @param contentView The contentView inside the sticker view.
		 *                     You can access it via the `contentView` property.
		 *
		 *  @return The sticker view.
		 */
		public  init(contentView: UIView) {
				self.defaultInset = 11
				self.defaultMinimumSize = 4 * self.defaultInset
				
				var frame = contentView.frame
				frame = CGRect(x: 0, y: 0, width: frame.size.width + CGFloat(self.defaultInset) * 2, height: frame.size.height + CGFloat(self.defaultInset) * 2)
				super.init(frame: frame)
				self.backgroundColor = UIColor.clear
				self.addGestureRecognizer(self.moveGesture)
				self.addGestureRecognizer(self.tapGesture)
				
				// Setup content view
				self.contentView = contentView
				self.contentView.center = CGRectGetCenter(self.bounds)
				self.contentView.isUserInteractionEnabled = false
				self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
				self.contentView.layer.allowsEdgeAntialiasing = true
				self.addSubview(self.contentView)
				
				// Setup editing handlers
				self.setPosition(.topRight, forHandler: .close)
				self.addSubview(self.closeImageView)
				self.setPosition(.bottomRight, forHandler: .resize)
				self.addSubview(self.resizeImageView)
				self.setPosition(.bottomLeft, forHandler: .rotate)
				self.addSubview(self.rotateImageView)
				self.setPosition(.topLeft, forHandler: .flip)
				self.addSubview(self.flipImageView)
				
				self.showEditingHandlers = true
				self.enableClose = true
				self.enableRotate = true
				self.enableFlip = true
				self.enableResize = true
				
				self.minimumSize = self.defaultMinimumSize
				self.outlineBorderColor = .brown
		}
		
		public  required init?(coder aDecoder: NSCoder) {
				fatalError("init(coder:) has not been implemented")
		}
		
		/**
		 *  Use image to customize each editing handler.
		 *  It is your responsibility to set image for every editing handler.
		 *
		 *  @param image   The image to be used.
		 *  @param handler The editing handler.
		 */
		public func setImage(_ image:UIImage, forHandler handler:StickerViewHandler) {
				switch handler {
				case .close:
						self.closeImageView.image = image
				case .rotate:
						self.rotateImageView.image = image
				case .resize:
						self.resizeImageView.image = image
				case .flip:
						self.flipImageView.image = image
				}
		}
		
		/**
		 *  Customize each editing handler's position.
		 *  If not set, default position will be used.
		 *  @note  It is your responsibility not to set duplicated position.
		 *
		 *  @param position The position for the handler.
		 *  @param handler  The editing handler.
		 */
		
		public func setPosition(_ position:StickerViewPosition, forHandler handler:StickerViewHandler) {
				let origin = self.contentView.frame.origin
				let size = self.contentView.frame.size
				
				var handlerView:UIImageView?
				switch handler {
				case .close:
						handlerView = self.closeImageView
				case .rotate:
						handlerView = self.rotateImageView
				case .resize:
						handlerView = self.resizeImageView
				case .flip:
						handlerView = self.flipImageView
				}
				
				switch position {
				case .topLeft:
						handlerView?.center = origin
						handlerView?.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
				case .topRight:
						handlerView?.center = CGPoint(x: origin.x + size.width, y: origin.y)
						handlerView?.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
				case .bottomLeft:
						handlerView?.center = CGPoint(x: origin.x, y: origin.y + size.height)
						handlerView?.autoresizingMask = [.flexibleRightMargin, .flexibleTopMargin]
				case .bottomRight:
						handlerView?.center = CGPoint(x: origin.x + size.width, y: origin.y + size.height)
						handlerView?.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
				}
				
				handlerView?.tag = position.rawValue
		}
		
		/**
		 *  Customize handler's size
		 *
		 *  @param size Handler's size
		 */
		public func setHandlerSize(_ size:Int) {
				if size <= 0 {
						return
				}
				
				self.defaultInset = NSInteger(round(Float(size) / 2))
				self.defaultMinimumSize = 4 * self.defaultInset
				self.minimumSize = max(self.minimumSize, self.defaultMinimumSize)
				
				let originalCenter = self.center
				let originalTransform = self.transform
				var frame = self.contentView.frame
				frame = CGRect(x: 0, y: 0, width: frame.size.width + CGFloat(self.defaultInset) * 2, height: frame.size.height + CGFloat(self.defaultInset) * 2)
				
				self.contentView.removeFromSuperview()
				
				self.transform = CGAffineTransform.identity
				self.frame = frame
				
				self.contentView.center = CGRectGetCenter(self.bounds)
				self.addSubview(self.contentView)
				self.sendSubviewToBack(self.contentView)
				
				let handlerFrame = CGRect(x: 0, y: 0, width: self.defaultInset * 2, height: self.defaultInset * 2)
			
				self.closeImageView.frame = handlerFrame
				self.setPosition(StickerViewPosition(rawValue: self.closeImageView.tag)!, forHandler: .close)
				self.rotateImageView.frame = handlerFrame
				self.setPosition(StickerViewPosition(rawValue: self.rotateImageView.tag)!, forHandler: .rotate)
				self.resizeImageView.frame = handlerFrame
				self.setPosition(StickerViewPosition(rawValue: self.resizeImageView.tag)!, forHandler: .resize)
				self.flipImageView.frame = handlerFrame
				self.setPosition(StickerViewPosition(rawValue: self.flipImageView.tag)!, forHandler: .flip)
				
				self.center = originalCenter
				self.transform = originalTransform
		}
		
		/**
		 *  Default value
		 */
		private var defaultInset:NSInteger
		private var defaultMinimumSize:NSInteger
		
		/**
		 *  Variables for moving viewes
		 */
		private var beginningPoint = CGPoint.zero
		private var beginningCenter = CGPoint.zero
		
		/**
		 *  Variables for rotating and resizing viewes
		 */
		private var initialBounds = CGRect.zero
		private var initialDistance:CGFloat = 0
		private var deltaAngle:CGFloat = 0
		
		private lazy var moveGesture = {
				return UIPanGestureRecognizer(target: self, action: #selector(handleMoveGesture(_:)))
		}()
		private lazy var rotateImageView:UIImageView = {
				let rotateImageView = UIImageView(frame: CGRect(x: 0, y: 0, width: self.defaultInset * 2, height: self.defaultInset * 2))
				rotateImageView.contentMode = UIView.ContentMode.scaleAspectFit
				rotateImageView.backgroundColor = UIColor.clear
				rotateImageView.isUserInteractionEnabled = true
				rotateImageView.addGestureRecognizer(self.rotateGesture)
				
				return rotateImageView
		}()
		
	private lazy var resizeImageView:UIImageView = {
			let resizeImageView = UIImageView(frame: CGRect(x: 0, y: 0, width: self.defaultInset * 2, height: self.defaultInset * 2))
		resizeImageView.contentMode = UIView.ContentMode.scaleAspectFit
		resizeImageView.backgroundColor = UIColor.clear
		resizeImageView.isUserInteractionEnabled = true
		resizeImageView.addGestureRecognizer(self.resizeGesture)
			
			return resizeImageView
	}()
	
		private lazy var rotateGesture = {
				return UIPanGestureRecognizer(target: self, action: #selector(handleRotateGesture(_:)))
		}()
	
	private lazy var resizeGesture = {
			return UIPanGestureRecognizer(target: self, action: #selector(handleResizeGesture(_:)))
	}()
	
		private lazy var closeImageView:UIImageView = {
				let closeImageview = UIImageView(frame: CGRect(x: 0, y: 0, width: self.defaultInset * 2, height: self.defaultInset * 2))
				closeImageview.contentMode = UIView.ContentMode.scaleAspectFit
				closeImageview.backgroundColor = UIColor.clear
				closeImageview.isUserInteractionEnabled = true
				closeImageview.addGestureRecognizer(self.closeGesture)
				return closeImageview
		}()
		private lazy var closeGesture = {
				return UITapGestureRecognizer(target: self, action: #selector(handleCloseGesture(_:)))
		}()
		private lazy var flipImageView:UIImageView = {
				let flipImageView = UIImageView(frame: CGRect(x: 0, y: 0, width: self.defaultInset * 2, height: self.defaultInset * 2))
				flipImageView.contentMode = UIView.ContentMode.scaleAspectFit
				flipImageView.backgroundColor = UIColor.clear
				flipImageView.isUserInteractionEnabled = true
				flipImageView.addGestureRecognizer(self.flipGesture)
				return flipImageView
		}()
		private lazy var flipGesture = {
				return UITapGestureRecognizer(target: self, action: #selector(handleFlipGesture(_:)))
		}()
		private lazy var tapGesture = {
				return UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
		}()
		// MARK: - Gesture Handlers
		@objc
		func handleMoveGesture(_ recognizer: UIPanGestureRecognizer) {
				let touchLocation = recognizer.location(in: self.superview)
				switch recognizer.state {
				case .began:
						self.beginningPoint = touchLocation
						self.beginningCenter = self.center
						if let delegate = self.delegate {
								delegate.stickerViewDidBeginMoving(self)
						}
				case .changed:
						self.center = CGPoint(x: self.beginningCenter.x + (touchLocation.x - self.beginningPoint.x), y: self.beginningCenter.y + (touchLocation.y - self.beginningPoint.y))
						if let delegate = self.delegate {
								delegate.stickerViewDidChangeMoving(self)
						}
				case .ended:
						self.center = CGPoint(x: self.beginningCenter.x + (touchLocation.x - self.beginningPoint.x), y: self.beginningCenter.y + (touchLocation.y - self.beginningPoint.y))
						if let delegate = self.delegate {
								delegate.stickerViewDidEndMoving(self)
						}
				default:
						break
				}
		}
	
	@objc
	func handleResizeGesture(_ recognizer: UIPanGestureRecognizer) {
			let touchLocation = recognizer.location(in: self.superview)
			let center = self.center
			
			switch recognizer.state {
			case .began:
					self.deltaAngle = CGFloat(atan2f(Float(touchLocation.y - center.y), Float(touchLocation.x - center.x))) - CGAffineTransformGetAngle(self.transform)
					self.initialBounds = self.bounds
					self.initialDistance = CGPointGetDistance(point1: center, point2: touchLocation)
					if let delegate = self.delegate {
							delegate.stickerViewDidBeginResizing(self)
					}
			case .changed:
					var scale = CGPointGetDistance(point1: center, point2: touchLocation) / self.initialDistance
					let minimumScale = CGFloat(self.minimumSize) / min(self.initialBounds.size.width, self.initialBounds.size.height)
					scale = max(scale, minimumScale)
					let scaledBounds = CGRectScale(self.initialBounds, wScale: scale, hScale: scale)
					self.bounds = scaledBounds
					self.setNeedsDisplay()
					
					if let delegate = self.delegate {
							delegate.stickerViewDidChangeResizing(self)
					}
			case .ended:
					if let delegate = self.delegate {
							delegate.stickerViewDidEndResizing(self)
					}
			default:
					break
			}
	}
		
		@objc
		func handleRotateGesture(_ recognizer: UIPanGestureRecognizer) {
				let touchLocation = recognizer.location(in: self.superview)
				let center = self.center
				
				switch recognizer.state {
				case .began:
						self.deltaAngle = CGFloat(atan2f(Float(touchLocation.y - center.y), Float(touchLocation.x - center.x))) - CGAffineTransformGetAngle(self.transform)
						self.initialBounds = self.bounds
						self.initialDistance = CGPointGetDistance(point1: center, point2: touchLocation)
						if let delegate = self.delegate {
								delegate.stickerViewDidBeginRotating(self)
						}
				case .changed:
						let angle = atan2f(Float(touchLocation.y - center.y), Float(touchLocation.x - center.x))
						let angleDiff = Float(self.deltaAngle) - angle
						print("angle -> \(angle)")
						print("angleDiff -> \(angleDiff)")
						print("final -> \(CGAffineTransform(rotationAngle: CGFloat(-angleDiff)))")
						
							snappingImageWhenRotating(angleDiff: angleDiff)
						

					
						if let delegate = self.delegate {
								delegate.stickerViewDidChangeRotating(self)
						}
				case .ended:
						if let delegate = self.delegate {
								delegate.stickerViewDidEndRotating(self)
						}
				default:
						break
				}
		}
		
		@objc
		func handleCloseGesture(_ recognizer: UITapGestureRecognizer) {
				if let delegate = self.delegate {
						delegate.stickerViewDidClose(self)
				}
				self.removeFromSuperview()
		}
		
		@objc
		func handleFlipGesture(_ recognizer: UITapGestureRecognizer) {
				UIView.animate(withDuration: 0.3) {
						self.contentView.transform = self.contentView.transform.scaledBy(x: -1, y: 1)
				}
		}
		
		@objc
		func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
				if let delegate = self.delegate {
						delegate.stickerViewDidTap(self)
				}
		}
		
		// MARK: - Private Methods
		private func setEnableClose(_ enableClose:Bool) {
				self.closeImageView.isHidden = !enableClose
				self.closeImageView.isUserInteractionEnabled = enableClose
		}
		
		private func setEnableRotate(_ enableRotate:Bool) {
				self.rotateImageView.isHidden = !enableRotate
				self.rotateImageView.isUserInteractionEnabled = enableRotate
		}
		
		private func setEnableFlip(_ enableFlip:Bool) {
				self.flipImageView.isHidden = !enableFlip
				self.flipImageView.isUserInteractionEnabled = enableFlip
		}
	
	private func setEnableResize(_ enableResize:Bool) {
			self.resizeImageView.isHidden = !enableResize
			self.resizeImageView.isUserInteractionEnabled = enableResize
	}
	
	private func snappingImageWhenRotating(angleDiff: Float) {
		if angleDiff < -0.60 && angleDiff > -0.80 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-0.80)))
		} else if angleDiff > -1.00 && angleDiff < -0.80 {
			self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-0.80)))
		}
		else if angleDiff < -1.40 && angleDiff > -1.57 {
			self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-1.57)))

		} else if angleDiff > -1.70 && angleDiff < -1.57 {
			self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-1.57)))
		}

		else if angleDiff < -2.15 && angleDiff > -2.35 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-2.35)))
		} else if angleDiff > -2.55 && angleDiff < -2.35 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-2.35)))
		}

		else if angleDiff < -2.94 && angleDiff > -3.14 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-3.14)))
		} else if angleDiff > -3.34 && angleDiff < -3.14 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-3.14)))
		}

		else if angleDiff < -3.72 && angleDiff > -3.92 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-3.92)))
		} else if angleDiff > -4.12 && angleDiff < -3.92 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-3.92)))
		}
		
		else if angleDiff < -4.50 && angleDiff > -4.70 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-4.70)))
		} else if angleDiff > -4.90 && angleDiff < -4.70 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-4.70)))
		}
		
		
		else if angleDiff < -5.30 && angleDiff > -5.50 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-5.50)))
		} else if angleDiff > -5.70 && angleDiff < -5.50 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-5.50)))
		}
		
		
		else if angleDiff < -6.28 && angleDiff > -6.28 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-6.28)))
		} else if angleDiff > -6.48 && angleDiff < -6.28 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(-6.28)))
		}

		// reverse side
		
		
		else if angleDiff > 5.32 && angleDiff < 5.52 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(5.52)))
		} else if angleDiff < 5.72 && angleDiff > 5.52 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(5.52)))
		}

		else if angleDiff > 4.51 && angleDiff < 4.71 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(4.71)))
		} else if angleDiff < 4.91 && angleDiff > 4.71 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(4.71)))
		}
		
		else if angleDiff > 3.69 && angleDiff < 3.89 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(3.89)))
		} else if angleDiff < 4.09 && angleDiff > 3.89 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(3.89)))
		}
		
		else if angleDiff > 2.93 && angleDiff < 3.13 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(3.13)))
		} else if angleDiff < 3.33 && angleDiff > 3.13 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(3.13)))
		}
		
		else if angleDiff > 2.15 && angleDiff < 2.35 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(2.35)))
		} else if angleDiff < 2.55 && angleDiff > 2.35 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(2.35)))
		}
		
		else if angleDiff > 1.37 && angleDiff < 1.57 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(1.57)))
		} else if angleDiff < 1.77 && angleDiff > 1.57 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(1.57)))
		}


		else if angleDiff > 0.57 && angleDiff < 0.77 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(0.77)))
		} else if angleDiff < 0.97 && angleDiff > 0.77 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(0.77)))
		}

		else if angleDiff > 0.2 && angleDiff < 0.00 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(0.00)))
		} else if angleDiff < 0.2 && angleDiff > 0.00 {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-(0.00)))
		}
		else {
				self.transform = CGAffineTransform(rotationAngle: CGFloat(-angleDiff))
		}
	}
}

extension StickerView: UIGestureRecognizerDelegate {
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
				return true
		}
}
