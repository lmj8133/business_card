import AVFoundation
import SwiftUI
import UIKit
import Vision

/// Live camera preview with a fixed card-alignment guide overlay.
struct CameraView: UIViewControllerRepresentable {
    /// Callback with the captured image and whether to skip card detection in OCR.
    let onCapture: (CIImage, Bool) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Camera View Controller

final class CameraViewController: UIViewController {
    var onCapture: ((CIImage, Bool) -> Void)?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // Guide overlay layers
    private let dimmingLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()
    private let cornerMarkLayer = CAShapeLayer()
    private let instructionLabel = UILabel()
    private let captureButton = UIButton(type: .system)

    // ISO 7810 ID-1 (85.6mm × 53.98mm) — covers credit cards, most business cards, and IDs
    private let cardAspectRatio: CGFloat = 1.586
    private let guideWidthRatio: CGFloat = 0.4          // guide width as fraction of available width
    private let guideCornerRadius: CGFloat = 10
    private let buttonAreaSize: CGFloat = 100    // reserved space for capture button (bottom in portrait, right in landscape)
    private let cornerMarkLength: CGFloat = 30            // L-shaped corner mark length
    private let cornerMarkLineWidth: CGFloat = 4.0        // corner mark line width
    private let cornerMarkInset: CGFloat = -3             // negative = outward offset (KYC style)

    // Real-time card detection overlay
    private let detectionLayer = CAShapeLayer()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "camera.processing")

    // Smoothing: low-pass filter for corner positions
    private var smoothedCorners: [CGPoint]?
    private let smoothingFactor: CGFloat = 0.3

    // Delayed disappearance: wait N frames before hiding overlay
    private var noDetectionCount = 0
    private let hideThreshold = 10

    // Latest rectangle observation from real-time detection (main queue only)
    private var lastObservation: VNRectangleObservation?

    // MARK: - Orientation support

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var shouldAutorotate: Bool { true }

    /// Whether the current layout is portrait (height > width).
    private var isPortrait: Bool { view.bounds.height > view.bounds.width }

    /// Guide rectangle in view coordinates.
    /// The guide always uses a landscape card aspect ratio (width > height).
    /// Portrait: button area reserved at bottom; guide uses a smaller width ratio for comfortable focus distance.
    /// Landscape: button area reserved on the right.
    private var guideRect: CGRect {
        let bounds = view.bounds
        let padding: CGFloat = 40
        let portrait = isPortrait

        // Available area excludes the capture-button strip
        let availableWidth  = portrait ? bounds.width : (bounds.width - buttonAreaSize)
        let availableHeight = portrait ? (bounds.height - buttonAreaSize) : bounds.height

        // Portrait uses a smaller ratio so the card doesn't need to be too close to focus
        let widthRatio: CGFloat = portrait ? 0.85 : guideWidthRatio

        var guideWidth = availableWidth * widthRatio
        var guideHeight = guideWidth / cardAspectRatio

        // Clamp width
        if guideWidth > availableWidth - padding {
            guideWidth = availableWidth - padding
            guideHeight = guideWidth / cardAspectRatio
        }
        // Clamp height
        if guideHeight > availableHeight - padding {
            guideHeight = availableHeight - padding
            guideWidth = guideHeight * cardAspectRatio
        }

        let x = (availableWidth - guideWidth) / 2
        let y = (availableHeight - guideHeight) / 2
        return CGRect(x: x, y: y, width: guideWidth, height: guideHeight)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupOverlay()
        setupCaptureButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        detectionLayer.frame = view.bounds
        updateVideoOrientation()
        updateOverlayPaths()
        updateCaptureButtonPosition()
    }

    // MARK: - Setup

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(photoOutput) { captureSession.addOutput(photoOutput) }

        // Video output for real-time card detection
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        updateVideoOrientation()
    }

    private func setupOverlay() {
        // Dimming layer: semi-transparent mask with cutout
        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        view.layer.addSublayer(dimmingLayer)

        // Guide border — subtle line so corner marks stand out (KYC style)
        guideLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        guideLayer.lineWidth = 1.0
        guideLayer.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(guideLayer)

        // Corner marks — thicker and longer for KYC prominence
        cornerMarkLayer.strokeColor = UIColor.white.cgColor
        cornerMarkLayer.lineWidth = cornerMarkLineWidth
        cornerMarkLayer.lineCap = .round
        cornerMarkLayer.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(cornerMarkLayer)

        // Instruction label
        instructionLabel.text = "Align card within the frame"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        instructionLabel.textAlignment = .center
        instructionLabel.layer.shadowColor = UIColor.black.cgColor
        instructionLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        instructionLabel.layer.shadowOpacity = 0.8
        instructionLabel.layer.shadowRadius = 2
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        // Real-time card detection overlay (green quadrilateral)
        detectionLayer.strokeColor = UIColor.systemGreen.cgColor
        detectionLayer.lineWidth = 3
        detectionLayer.lineJoin = .round
        detectionLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.1).cgColor
        detectionLayer.opacity = 0
        view.layer.addSublayer(detectionLayer)

        addCornerPulseAnimation()
    }

    /// Subtle pulse animation on corner marks for a professional KYC feel.
    private func addCornerPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.5
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cornerMarkLayer.add(pulse, forKey: "cornerPulse")
    }

    /// Sync the preview layer's video orientation with the current interface orientation.
    private func updateVideoOrientation() {
        guard let previewConnection = previewLayer?.connection,
              previewConnection.isVideoOrientationSupported,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }

        let orientation: AVCaptureVideoOrientation = {
            switch scene.interfaceOrientation {
            case .portrait:            return .portrait
            case .portraitUpsideDown:   return .portraitUpsideDown
            case .landscapeLeft:       return .landscapeLeft
            case .landscapeRight:      return .landscapeRight
            default:                   return .portrait
            }
        }()

        previewConnection.videoOrientation = orientation

        // Sync photo output so EXIF orientation matches the device orientation.
        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoOrientationSupported {
            photoConnection.videoOrientation = orientation
        }
    }

    private func updateOverlayPaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = guideRect

        // Dimming: full-screen path with rounded-rect cutout (even-odd fill)
        let fullPath = UIBezierPath(rect: view.bounds)
        let cutout = UIBezierPath(roundedRect: rect, cornerRadius: guideCornerRadius)
        fullPath.append(cutout)
        dimmingLayer.path = fullPath.cgPath
        dimmingLayer.frame = view.bounds

        // Guide border
        guideLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: guideCornerRadius).cgPath
        guideLayer.frame = view.bounds

        // Corner marks: L-shaped marks at each corner with outward offset (KYC style)
        let d = cornerMarkInset   // negative = marks extend outside the guide rect
        let m = cornerMarkLength
        let cornerPath = UIBezierPath()

        // Top-left
        cornerPath.move(to: CGPoint(x: rect.minX + d, y: rect.minY + m))
        cornerPath.addLine(to: CGPoint(x: rect.minX + d, y: rect.minY + d))
        cornerPath.addLine(to: CGPoint(x: rect.minX + m, y: rect.minY + d))

        // Top-right
        cornerPath.move(to: CGPoint(x: rect.maxX - m, y: rect.minY + d))
        cornerPath.addLine(to: CGPoint(x: rect.maxX - d, y: rect.minY + d))
        cornerPath.addLine(to: CGPoint(x: rect.maxX - d, y: rect.minY + m))

        // Bottom-right
        cornerPath.move(to: CGPoint(x: rect.maxX - d, y: rect.maxY - m))
        cornerPath.addLine(to: CGPoint(x: rect.maxX - d, y: rect.maxY - d))
        cornerPath.addLine(to: CGPoint(x: rect.maxX - m, y: rect.maxY - d))

        // Bottom-left
        cornerPath.move(to: CGPoint(x: rect.minX + m, y: rect.maxY - d))
        cornerPath.addLine(to: CGPoint(x: rect.minX + d, y: rect.maxY - d))
        cornerPath.addLine(to: CGPoint(x: rect.minX + d, y: rect.maxY - m))

        cornerMarkLayer.path = cornerPath.cgPath
        cornerMarkLayer.frame = view.bounds

        // Instruction label position: below the guide rect, centered within guide area
        let labelWidth = isPortrait ? view.bounds.width : (view.bounds.width - buttonAreaSize)
        instructionLabel.frame = CGRect(
            x: 0,
            y: rect.maxY + 16,
            width: labelWidth,
            height: 20
        )
        CATransaction.commit()
    }

    private func setupCaptureButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 60, weight: .light)
        captureButton.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: config), for: .normal)
        captureButton.tintColor = .white
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.sizeToFit()
        view.addSubview(captureButton)
    }

    /// Position the capture button: bottom-center in portrait, right-center in landscape.
    private func updateCaptureButtonPosition() {
        let bounds = view.bounds
        let safeArea = view.safeAreaInsets
        let btnSize = captureButton.bounds.size

        if isPortrait {
            captureButton.center = CGPoint(
                x: bounds.midX,
                y: bounds.height - safeArea.bottom - 16 - btnSize.height / 2
            )
        } else {
            captureButton.center = CGPoint(
                x: bounds.width - safeArea.right - 16 - btnSize.width / 2,
                y: bounds.midY
            )
        }
    }

    // MARK: - Guide Region

    /// Guide frame as a Vision-coordinate regionOfInterest (origin bottom-left, normalized 0-1).
    ///
    /// `metadataOutputRectConverted` returns AVFoundation coords (origin top-left, 0-1).
    /// `VNImageBasedRequest.regionOfInterest` expects Vision coords (origin bottom-left, 0-1)
    /// when the request handler is initialized with a `CVPixelBuffer`.
    private var guideRegionOfInterest: CGRect {
        guard let previewLayer else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let avRect = previewLayer.metadataOutputRectConverted(fromLayerRect: guideRect)
        // AVFoundation (top-left origin) → Vision (bottom-left origin): flip Y
        return CGRect(
            x: avRect.origin.x,
            y: 1 - avRect.origin.y - avRect.height,
            width: avRect.width,
            height: avRect.height
        )
    }

    // MARK: - Capture

    /// Snapshot of guide rect in *view* coordinates at capture time.
    private var capturedGuideRect: CGRect = .zero
    /// Snapshot of preview layer bounds at capture time.
    private var capturedPreviewBounds: CGRect = .zero
    /// Snapshot of rectangle observation at capture time.
    private var capturedObservation: VNRectangleObservation?

    @objc private func capturePhoto() {
        // Snapshot geometry in view coordinates before capture
        capturedGuideRect = guideRect
        capturedPreviewBounds = previewLayer.bounds
        capturedObservation = lastObservation
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Perspective Correction

    /// Apply perspective correction using a rectangle observation from real-time detection.
    ///
    /// VNDetectRectanglesRequest (current revision) returns corner points in full-image
    /// normalized coordinates even when regionOfInterest is set. We convert directly
    /// from normalized to pixel coordinates.
    ///
    /// **Important**: The input `ciImage` must be the raw sensor image (before EXIF orientation).
    /// Video-frame detection runs on the raw `CVPixelBuffer`, so observation coordinates
    /// are in raw sensor space. Applying EXIF orientation first would swap width/height
    /// and produce an incorrect crop. Apply EXIF *after* perspective correction.
    private func perspectiveCorrect(
        ciImage: CIImage,
        observation: VNRectangleObservation
    ) -> CIImage? {
        let ext = ciImage.extent
        guard ext.width > 0, ext.height > 0 else { return nil }

        // Full-image normalized → pixel (CIImage bottom-left origin)
        func toPixel(_ pt: CGPoint) -> CGPoint {
            CGPoint(x: pt.x * ext.width + ext.origin.x,
                    y: pt.y * ext.height + ext.origin.y)
        }

        let tl = toPixel(observation.topLeft)
        let tr = toPixel(observation.topRight)
        let bl = toPixel(observation.bottomLeft)
        let br = toPixel(observation.bottomRight)

        let corrected = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft":     CIVector(cgPoint: tl),
            "inputTopRight":    CIVector(cgPoint: tr),
            "inputBottomLeft":  CIVector(cgPoint: bl),
            "inputBottomRight": CIVector(cgPoint: br),
        ])
        guard corrected.extent.width > 0, corrected.extent.height > 0 else { return nil }
        return corrected
    }

    // MARK: - Guide Crop

    /// Crop a CIImage to the guide frame area with padding for Vision rectangle detection.
    ///
    /// The preview layer uses `.resizeAspectFill`, so the camera feed is
    /// scaled uniformly until it covers the entire layer — part of the image
    /// is clipped on the shorter axis. We replicate that mapping here so the
    /// guide rectangle maps to the correct pixel region of the (already
    /// orientation-corrected) captured image.
    private func cropToGuideFrame(ciImage: CIImage) -> CIImage {
        let ext = ciImage.extent
        guard ext.width > 0, ext.height > 0 else { return ciImage }

        let layerSize = capturedPreviewBounds.size
        guard layerSize.width > 0, layerSize.height > 0 else { return ciImage }

        // resizeAspectFill: scale = max so the image fully covers the layer
        let scaleX = ext.width  / layerSize.width
        let scaleY = ext.height / layerSize.height
        let scale  = max(scaleX, scaleY)

        // The visible portion of the image is centered in the layer
        let visibleWidth  = layerSize.width  * scale
        let visibleHeight = layerSize.height * scale
        let offsetX = (ext.width  - visibleWidth)  / 2 + ext.origin.x
        let offsetY = (ext.height - visibleHeight) / 2 + ext.origin.y

        let guide = capturedGuideRect

        // Add padding so Vision has background context for rectangle detection
        let padX = guide.width  * 0.08
        let padY = guide.height * 0.08

        // Map guide rect (view coords, top-left origin) to CIImage (bottom-left origin)
        let ciX = offsetX + (guide.origin.x - padX) * scale
        let ciY = offsetY + (layerSize.height - guide.origin.y - guide.height - padY) * scale
        let ciW = (guide.width  + padX * 2) * scale
        let ciH = (guide.height + padY * 2) * scale

        let cropRect = CGRect(x: ciX, y: ciY, width: ciW, height: ciH)
        let clamped = cropRect.intersection(ext)
        guard !clamped.isNull, !clamped.isEmpty else { return ciImage }
        return ciImage.cropped(to: clamped)
    }
}

// MARK: - Photo Capture Delegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let ciImage = CIImage(data: data)
        else { return }

        // Read EXIF orientation (apply later, after perspective correction)
        let cgOrientation: CGImagePropertyOrientation?
        if let val = ciImage.properties[kCGImagePropertyOrientation as String] as? UInt32 {
            cgOrientation = CGImagePropertyOrientation(rawValue: val)
        } else {
            cgOrientation = nil
        }

        // Perspective correction on RAW image (same coordinate space as video frame detection).
        // Observation coords are in raw sensor space; applying EXIF first would swap width/height.
        if let obs = capturedObservation,
           let corrected = perspectiveCorrect(ciImage: ciImage, observation: obs) {
            let finalImage: CIImage
            if let orientation = cgOrientation {
                finalImage = corrected.oriented(orientation).baked()
            } else {
                finalImage = corrected
            }
            DispatchQueue.main.async { [weak self] in
                self?.onCapture?(finalImage, true)
            }
            return
        }

        // Fallback: cropToGuideFrame needs oriented image (preview layer maps view coords to oriented space)
        let oriented: CIImage
        if let orientation = cgOrientation {
            oriented = ciImage.oriented(orientation).baked()
        } else {
            oriented = ciImage
        }
        let cropped = cropToGuideFrame(ciImage: oriented)
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(cropped, false)
        }
    }
}

// MARK: - Real-time Card Detection

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Restrict detection to the guide frame area
        let roi = guideRegionOfInterest

        let request = VNDetectRectanglesRequest { [weak self] req, _ in
            guard let results = req.results as? [VNRectangleObservation],
                  let rect = results.first
            else {
                DispatchQueue.main.async {
                    self?.handleNoDetection()
                }
                return
            }
            DispatchQueue.main.async {
                self?.lastObservation = rect
                self?.drawDetectionOverlay(for: rect)
            }
        }
        // Match the aspect ratio range used in VisionOCREngine
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 0.9
        request.minimumSize = 0.15
        request.maximumObservations = 1
        request.minimumConfidence = 0.7
        request.regionOfInterest = roi

        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }

    private func handleNoDetection() {
        noDetectionCount += 1
        if noDetectionCount > hideThreshold {
            lastObservation = nil
            smoothedCorners = nil
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            detectionLayer.opacity = 0
            CATransaction.commit()
        }
    }

    private func drawDetectionOverlay(for observation: VNRectangleObservation) {
        guard let previewLayer else { return }
        noDetectionCount = 0

        // VNDetectRectanglesRequest (current revision) returns corner points
        // in full-image normalized coordinates even when regionOfInterest is set.
        // Vision coords (bottom-left origin) → AVFoundation (top-left origin): flip Y.
        let convert = { (point: CGPoint) -> CGPoint in
            previewLayer.layerPointConverted(
                fromCaptureDevicePoint: CGPoint(x: point.x, y: 1 - point.y)
            )
        }

        let newCorners = [
            convert(observation.topLeft),
            convert(observation.topRight),
            convert(observation.bottomRight),
            convert(observation.bottomLeft),
        ]

        // Apply low-pass filter for smooth tracking
        if let prev = smoothedCorners {
            smoothedCorners = zip(prev, newCorners).map { prev, new in
                CGPoint(
                    x: prev.x + (new.x - prev.x) * smoothingFactor,
                    y: prev.y + (new.y - prev.y) * smoothingFactor
                )
            }
        } else {
            smoothedCorners = newCorners
        }

        guard let corners = smoothedCorners else { return }

        let path = UIBezierPath()
        path.move(to: corners[0])
        path.addLine(to: corners[1])
        path.addLine(to: corners[2])
        path.addLine(to: corners[3])
        path.close()

        detectionLayer.path = path.cgPath

        // Restore opacity when detection resumes
        if detectionLayer.opacity < 1 {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            detectionLayer.opacity = 1
            CATransaction.commit()
        }
    }
}
