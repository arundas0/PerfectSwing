import AVFoundation
import UIKit

enum CameraServiceError: Error, CustomStringConvertible {
    case unauthorized
    case deviceUnavailable
    case cannotAddInput
    case cannotAddOutput
    case configurationFailed(String)
    case lockConfigurationFailed(Error)
    case runtimeError(Error)

    var description: String {
        switch self {
        case .unauthorized: return "Camera access was not authorized."
        case .deviceUnavailable: return "Requested camera device is unavailable."
        case .cannotAddInput: return "Failed to add camera input to the session."
        case .cannotAddOutput: return "Failed to add output to the session."
        case .configurationFailed(let reason): return "Camera configuration failed: \(reason)"
        case .lockConfigurationFailed(let error): return "Failed to lock device: \(error.localizedDescription)"
        case .runtimeError(let error): return "Runtime error: \(error.localizedDescription)"
        }
    }
}

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer)
}

class CameraService: NSObject, ObservableObject {
    weak var delegate: CameraServiceDelegate?
    var onError: ((CameraServiceError) -> Void)?
    
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
    private var observers: [NSObjectProtocol] = []
    
    @Published var isAuthorized = false
    @Published var isRunning = false
    
    override init() {
        super.init()
        checkPermissions()
        registerNotifications()
    }
    
    deinit {
        unregisterNotifications()
        stop()
    }
    
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.session.isRunning else { return }
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
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                self.session.commitConfiguration()
                self.onError?(.deviceUnavailable)
                print("Failed to find camera device")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.onError?(.cannotAddInput)
                    print("Failed to add camera input")
                    return
                }
                self.session.addInput(input)
            } catch {
                self.session.commitConfiguration()
                self.onError?(.configurationFailed("\(error.localizedDescription)"))
                print("Failed to create camera input: \(error)")
                return
            }

            // Output
            if self.session.canAddOutput(self.videoOutput) {
                if !self.session.outputs.contains(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                // MediaPipe requires BGRA format
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]

                if let connection = self.videoOutput.connection(with: .video) {
                    if #available(iOS 17.0, *) {
                        let angle = self.currentVideoRotationAngle()
                        if connection.isVideoRotationAngleSupported(angle) {
                            connection.videoRotationAngle = angle
                        }
                    } else {
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = self.currentVideoOrientation()
                        }
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }
            } else {
                self.session.commitConfiguration()
                self.onError?(.cannotAddOutput)
                print("Failed to add video output")
                return
            }

            self.session.commitConfiguration()
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
    
    func setPreferredFrameRate(_ fps: Int?) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                guard let fps = fps else {
                    device.activeVideoMinFrameDuration = CMTime.invalid
                    device.activeVideoMaxFrameDuration = CMTime.invalid
                    return
                }

                // Pick the highest resolution format that supports the desired fps
                let desired = Double(fps)
                let candidates = device.formats.filter { format in
                    format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= desired }
                }
                let best: AVCaptureDevice.Format? = candidates.max { lhs, rhs in
                    let dl = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
                    let dr = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
                    let lhsPixels: Int = Int(dl.width) * Int(dl.height)
                    let rhsPixels: Int = Int(dr.width) * Int(dr.height)
                    return lhsPixels < rhsPixels
                }
                if let best = best {
                    device.activeFormat = best
                }

                let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            } catch {
                self.onError?(.lockConfigurationFailed(error))
            }
        }
    }
    
    @available(iOS, deprecated: 17.0, message: "Use currentVideoRotationAngle instead")
    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
    
    @available(iOS 17.0, *)
    private func currentVideoRotationAngle() -> CGFloat {
        // Camera sensor is naturally landscape, so portrait needs 90° rotation
        switch UIDevice.current.orientation {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90  // Portrait
        }
    }

    private func updateConnectionsOrientation() {
        guard let connection = self.videoOutput.connection(with: .video) else { return }

        if #available(iOS 17.0, *) {
            let angle = self.currentVideoRotationAngle()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = self.currentVideoOrientation()
            }
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
    }

    private func registerNotifications() {
        let nc = NotificationCenter.default

        let orientationToken = nc.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleOrientationChange()
        }

        let runtimeErrorToken = nc.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
            self?.handleRuntimeError(note: note)
        }

        let interruptedToken = nc.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.handleSessionInterrupted()
        }

        let interruptionEndedToken = nc.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
            self?.handleInterruptionEnded()
        }

        observers.append(contentsOf: [orientationToken, runtimeErrorToken, interruptedToken, interruptionEndedToken])
    }
    
    private func handleOrientationChange() {
        sessionQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.updateConnectionsOrientation()
        }
    }

    private func handleRuntimeError(note: Notification) {
        let userInfoAny = note.userInfo
        let errorAny = userInfoAny?[AVCaptureSessionErrorKey]
        let avError = (errorAny as? AVError) ?? AVError(.unknown)

        let errorCallback = onError
        errorCallback?(.runtimeError(avError))

        let code = avError.code
        if code != .mediaServicesWereReset { return }

        sessionQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            let alreadyRunning = strongSelf.session.isRunning
            if !alreadyRunning {
                strongSelf.session.startRunning()
                let runningNow = strongSelf.session.isRunning
                DispatchQueue.main.async {
                    strongSelf.isRunning = runningNow
                }
            }
        }
    }

    private func handleSessionInterrupted() {
        isRunning = false
    }

    private func handleInterruptionEnded() {
        sessionQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            let wasRunning = strongSelf.session.isRunning
            if !wasRunning {
                strongSelf.session.startRunning()
                let nowRunning = strongSelf.session.isRunning
                DispatchQueue.main.async {
                    strongSelf.isRunning = nowRunning
                }
            }
        }
    }

    private func unregisterNotifications() {
        let nc = NotificationCenter.default
        for token in observers { nc.removeObserver(token) }
        observers.removeAll()
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
            onError?(.unauthorized)
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            debugFrameCount += 1
            if debugFrameCount <= 10 { print("🧪 CameraService.captureOutput start #\(debugFrameCount)") }
            delegate?.cameraService(self, didOutput: sampleBuffer)
            if debugFrameCount <= 10 { print("🧪 CameraService.captureOutput end #\(debugFrameCount)") }
        }
    }
}

