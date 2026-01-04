import Foundation
import MediaPipeTasksVision
import AVFoundation

class PoseDetector: NSObject, ObservableObject, CameraServiceDelegate, PoseLandmarkerLiveStreamDelegate {
    // We will publish the detected landmarks (normalized 0..1)
    @Published var landmarks: [[NormalizedLandmark]] = []
    
    private var poseLandmarker: PoseLandmarker?
    
    override init() {
        super.init()
        createLandmarker()
    }
    
    private func createLandmarker() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker", ofType: "task") else {
            print("❌ MODEL FILE NOT FOUND - Make sure pose_landmarker.task is in the bundle")
            return
        }
        print("✅ Model path found: \(modelPath)")
        
        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.5
            options.minPosePresenceConfidence = 0.5
            options.minTrackingConfidence = 0.5
            
            options.poseLandmarkerLiveStreamDelegate = self
            
            poseLandmarker = try PoseLandmarker(options: options)
            print("✅ PoseLandmarker created successfully")
        } catch {
            print("❌ Failed to create PoseLandmarker: \(error)")
        }
    }
    
    // Hooks for external logic
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onLandmarks: (([NormalizedLandmark]) -> Void)?
    
    // Debug metrics
    @Published var framesReceived: Int = 0
    @Published var detectionsAttempted: Int = 0
    @Published var resultsReceived: Int = 0
    @Published var lastError: String = ""
    
    // CameraServiceDelegate conformance
    private var frameCount = 0
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer) {
        frameCount += 1
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.framesReceived += 1
        }
        if frameCount % 60 == 1 {
            print("📷 Received frame #\(frameCount)")
        }
        onFrame?(sampleBuffer)
        detect(sampleBuffer: sampleBuffer)
    }
    
    private func detect(sampleBuffer: CMSampleBuffer) {
        guard let landmarker = poseLandmarker else {
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.lastError = "Landmarker not initialized"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.detectionsAttempted += 1
        }
        let timestampInMilliseconds = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
        
        do {
            let image = try MPImage(sampleBuffer: sampleBuffer)
            try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampInMilliseconds)
        } catch {
            print("❌ Detection failed: \(error)")
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.lastError = "Detection error: \(error.localizedDescription)"
            }
        }
    }
    
    // Smoothing storage
    private var smoothedLandmarks: [NormalizedLandmark]?
    private let smoothingAlpha: Float = 0.3 // Adjust for more/less smoothing
    
    // PoseLandmarkerLiveStreamDelegate conformance
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.resultsReceived += 1
        }
        
        guard let result = result, let detectedLandmarks = result.landmarks.first else { 
            if let error = error {
                print("Pose detection error: \(error)")
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.lastError = "Result error: \(error.localizedDescription)"
                }
            } else {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.lastError = "No pose detected in frame"
                }
            }
            return 
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.lastError = "✓ OK"
        }
        
        // Apply EMA smoothing
        let filtered = applySmoothing(to: detectedLandmarks)
        self.smoothedLandmarks = filtered

        // Update UI and trigger logic on main thread
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.landmarks = [filtered]
            self.onLandmarks?(filtered)
        }
    }
    
    private func applySmoothing(to newLandmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        guard let previous = smoothedLandmarks, previous.count == newLandmarks.count else {
            return newLandmarks
        }
        
        return zip(previous, newLandmarks).map { (prev, current) in
            return NormalizedLandmark(
                x: prev.x * (1.0 - smoothingAlpha) + current.x * smoothingAlpha,
                y: prev.y * (1.0 - smoothingAlpha) + current.y * smoothingAlpha,
                z: prev.z * (1.0 - smoothingAlpha) + current.z * smoothingAlpha,
                visibility: current.visibility,
                presence: current.presence
            )
        }
    }
}
