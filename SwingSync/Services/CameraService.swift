import AVFoundation
import UIKit

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer)
}

class CameraService: NSObject, ObservableObject {
    weak var delegate: CameraServiceDelegate?
    
    // Public access to the session for the preview layer if needed, 
    // though we might just process frames and draw purely in SwiftUI.
    // For this milestone, we often want a preview layer to check camera works easily, 
    // but the requirement "UI: CameraView ... with a custom Shape overlay" implies we might want
    // a background preview. 
    // Let's expose the session cleanly.
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.swingsync.cameraQueue")
    private let videoOutputQueue = DispatchQueue(label: "com.swingsync.videoOutputQueue", qos: .userInteractive)
    private var debugFrameCount = 0
    
    @Published var isAuthorized = false
    @Published var isRunning = false
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
                print("📹 Camera session started: \(self.session.isRunning)")
            }
        }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                print("📹 Camera session stopped")
            }
        }
    }
    
    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            
            // Input: Front Camera for "Mirror" effect
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                print("Failed to add camera input")
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            
            // Output
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                
                // MediaPipe requires BGRA format
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                
                if let connection = self.videoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    connection.isVideoMirrored = true 
                }
            }
            
            self.session.commitConfiguration()
            
            // Temporarily disable High FPS to debug frame delivery
            // self.configureHighFrameRate(for: device)
            print("✅ Camera session configured (standard FPS)")
        }
    }
    
    private func configureHighFrameRate(for device: AVCaptureDevice) {
        // Prioritize 120, then 60, then 30
        //let targetFPS: Double = 240 // Target highest possible
        var bestFormat: AVCaptureDevice.Format?
        var bestRange: AVFrameRateRange?
        
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= 60 { // interested in HFR
                    if bestFormat == nil {
                        bestFormat = format
                        bestRange = range
                    } else if let currentBest = bestRange {
                        if range.maxFrameRate > currentBest.maxFrameRate {
                            bestFormat = format
                            bestRange = range
                        }
                    }
                }
            }
        }
        
        if let format = bestFormat, let range = bestRange {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                // Set to max supported by this range, up to our target
                let duration = range.minFrameDuration
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
                print("Camera configured for High FPS: \(range.maxFrameRate)")
            } catch {
                print("Failed to configure High FPS: \(error)")
            }
        }
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            debugFrameCount += 1
            if debugFrameCount <= 10 {
                print("🧪 CameraService.captureOutput start #\(debugFrameCount)")
            }
            delegate?.cameraService(self, didOutput: sampleBuffer)
            if debugFrameCount <= 10 {
                print("🧪 CameraService.captureOutput end #\(debugFrameCount)")
            }
        }
    }
}
