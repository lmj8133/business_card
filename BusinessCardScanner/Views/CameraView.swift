import AVFoundation
import SwiftUI
import UIKit
import Vision

/// Live camera preview with real-time card detection overlay.
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (CIImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Camera View Controller

final class CameraViewController: UIViewController {
    var onCapture: ((CIImage) -> Void)?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoOutput = AVCaptureVideoDataOutput()

    // Card detection overlay
    private let overlayLayer = CAShapeLayer()
    private let processingQueue = DispatchQueue(label: "camera.processing")

    // Smoothing: low-pass filter for corner positions
    private var smoothedCorners: [CGPoint]?
    private let smoothingFactor: CGFloat = 0.3

    // Delayed disappearance: wait N frames before hiding overlay
    private var noDetectionCount = 0
    private let hideThreshold = 10

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
        overlayLayer.frame = view.bounds
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
    }

    private func setupOverlay() {
        overlayLayer.strokeColor = UIColor.systemGreen.cgColor
        overlayLayer.lineWidth = 3
        overlayLayer.lineJoin = .round
        overlayLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.1).cgColor
        overlayLayer.frame = view.bounds
        view.layer.addSublayer(overlayLayer)
    }

    private func setupCaptureButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: 60, weight: .light)
        button.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)

        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
        ])
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
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

        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(ciImage)
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

        let request = VNDetectRectanglesRequest { [weak self] req, _ in
            guard let results = req.results as? [VNRectangleObservation],
                  let rect = results.first
            else {
                DispatchQueue.main.async { self?.handleNoDetection() }
                return
            }
            DispatchQueue.main.async { self?.drawOverlay(for: rect) }
        }
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 0.75
        request.minimumSize = 0.15
        request.maximumObservations = 1
        request.minimumConfidence = 0.7

        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }

    private func handleNoDetection() {
        noDetectionCount += 1
        if noDetectionCount > hideThreshold {
            smoothedCorners = nil
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            overlayLayer.opacity = 0
            CATransaction.commit()
        }
    }

    private func drawOverlay(for observation: VNRectangleObservation) {
        guard let previewLayer else { return }
        noDetectionCount = 0

        // Convert Vision normalized coords → preview layer points
        // layerPointConverted handles .resizeAspectFill scaling correctly
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

        overlayLayer.path = path.cgPath

        // Restore opacity when detection resumes
        if overlayLayer.opacity < 1 {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            overlayLayer.opacity = 1
            CATransaction.commit()
        }
    }
}
