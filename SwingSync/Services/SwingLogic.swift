import Foundation
import MediaPipeTasksVision
import Combine

enum SwingState {
    case idle
    case address
    case backswing
    case downswing
    case impact
    case finish
}

class SwingLogic: ObservableObject {
    @Published var state: SwingState = .idle
    @Published var statusMessage: String = "Waiting for golfer..."
    
    // Config - TUNED VALUES
    private let addressThreshold = 45 // ~1.5s at 30fps (was 15)
    private let steadyThreshold: Float = 0.10 // Tighter jitter requirement (was 0.18)
    private let backswingTrigger: Float = 0.15 // Wrist must rise this much to start backswing (was 0.12)
    
    // Visibility thresholds
    private let minVisibility: Float = 0.6
    
    // State
    private var addressConfidence: Int = 0 
    private var lastWristY: Float = 0.0
    private var baselineWristY: Float = 0.0 
    private var previousLandmarks: [NormalizedLandmark]?
    
    // Callback
    var onVisualSwingDetected: (() -> Void)?
    
    private var processCount = 0
    
    // Positional Window for steadiness - track multiple body parts
    private var wristYHistory: [Float] = []
    private var shoulderYHistory: [Float] = []
    private let windowSize = 15 // Increased window for better averaging
    
    @Published var debugInfo: String = ""
    
    // Swing landmark storage for replay
    struct SwingFrame {
        let timestamp: TimeInterval
        let landmarks: [NormalizedLandmark]
    }
    @Published private(set) var swingLandmarks: [SwingFrame] = []
    private var swingStartTime: TimeInterval = 0

    func process(landmarks: [NormalizedLandmark]) {
        processCount += 1
        
        // Check for basic visibility - need full upper body
        guard landmarks.count > 28 else {
            DispatchQueue.main.async {
                self.statusMessage = "Step into full view"
                self.debugInfo = "Not enough landmarks"
            }
            resetAddressProgress()
            return 
        }
        
        // Key landmarks
        let nose = landmarks[0]
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        let leftWrist = landmarks[15]
        let rightWrist = landmarks[16]
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        
        // Visibility checks - require good visibility on key landmarks
        let shoulderVisibility = min(
            leftShoulder.visibility?.floatValue ?? 0,
            rightShoulder.visibility?.floatValue ?? 0
        )
        let wristVisibility = min(
            leftWrist.visibility?.floatValue ?? 0,
            rightWrist.visibility?.floatValue ?? 0
        )
        
        if shoulderVisibility < minVisibility || wristVisibility < minVisibility {
            if processCount % 10 == 0 {
                var lowVis: [String] = []
                if shoulderVisibility < minVisibility { lowVis.append("shoulders") }
                if wristVisibility < minVisibility { lowVis.append("wrists") }
                let reason = lowVis.joined(separator: " & ")
                DispatchQueue.main.async {
                    self.statusMessage = "Keep \(reason) visible"
                    self.debugInfo = "Visibility: S:\(String(format: "%.0f%%", shoulderVisibility*100)) W:\(String(format: "%.0f%%", wristVisibility*100)) (need 60%+)"
                }
            }
            resetAddressProgress()
            return
        }
        
        // Calculate key metrics
        let avgWristY = (leftWrist.y + rightWrist.y) / 2
        let avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let wristDistance = abs(leftWrist.x - rightWrist.x)
        
        // Update history windows
        wristYHistory.append(avgWristY)
        shoulderYHistory.append(avgShoulderY)
        if wristYHistory.count > windowSize { wristYHistory.removeFirst() }
        if shoulderYHistory.count > windowSize { shoulderYHistory.removeFirst() }
        
        // Calculate steadiness from multiple body parts
        let wristJitter = (wristYHistory.max() ?? 0) - (wristYHistory.min() ?? 0)
        let shoulderJitter = (shoulderYHistory.max() ?? 0) - (shoulderYHistory.min() ?? 0)
        let combinedJitter = max(wristJitter, shoulderJitter * 1.5) // Weight shoulder jitter higher
        let isSteady = combinedJitter < steadyThreshold
        
        // Golf stance validation
        let isGolfStance = validateGolfStance(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftWrist: leftWrist,
            rightWrist: rightWrist,
            leftHip: leftHip,
            rightHip: rightHip
        )
        
        // Update debug info
        if processCount % 3 == 0 {
            DispatchQueue.main.async {
                let stanceStr = isGolfStance ? "✓" : "✗"
                self.debugInfo = "Jitter: \(String(format: "%.3f", combinedJitter)) Stance:\(stanceStr) Conf:\(self.addressConfidence)/\(self.addressThreshold)"
            }
        }
        
        switch state {
        case .idle, .finish:
            if isSteady && isGolfStance {
                addressConfidence += 1
                let progress = min(100, Int((Double(addressConfidence) / Double(addressThreshold)) * 100))
                DispatchQueue.main.async {
                    self.statusMessage = "Hold address... \(progress)%"
                }
                
                if addressConfidence >= addressThreshold {
                    baselineWristY = avgWristY
                    transition(to: .address)
                    addressConfidence = 0
                }
            } else if isSteady && !isGolfStance {
                // Steady but not in golf stance
                addressConfidence = max(0, addressConfidence - 1)
                if processCount % 10 == 0 {
                    DispatchQueue.main.async {
                        self.statusMessage = "Take address position"
                    }
                }
            } else {
                // Not steady
                if addressConfidence > 0 {
                    addressConfidence = max(0, addressConfidence - 2) // Decay faster
                } else if processCount % 10 == 0 {
                    DispatchQueue.main.async {
                        self.statusMessage = combinedJitter > 0.3 ? "Too much movement" : "Waiting for golfer..."
                    }
                }
            }
            
        case .address:
            DispatchQueue.main.async { self.statusMessage = "READY: Swing Now!" }
            // Detect backswing start - wrist rises (y decreases in screen coords, but MediaPipe has 0 at top)
            // Actually for front-facing camera with mirroring, need to check wrist movement
            if (baselineWristY - avgWristY) > backswingTrigger { 
                // Start recording swing landmarks
                swingStartTime = Date().timeIntervalSince1970
                swingLandmarks.removeAll()
                
                transition(to: .backswing)
                
                // Timeout safety - if stuck in backswing/downswing, auto-complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    if self?.state == .backswing || self?.state == .downswing {
                        self?.transition(to: .finish)
                        self?.onVisualSwingDetected?()
                    }
                }
            }
            
        case .backswing:
            DispatchQueue.main.async { self.statusMessage = "Backswing..." }
            // Store landmarks for replay
            let frame = SwingFrame(timestamp: Date().timeIntervalSince1970 - swingStartTime, landmarks: landmarks)
            swingLandmarks.append(frame)
            
            // Detect transition to downswing - wrist starts coming back down
            if avgWristY > (baselineWristY - 0.10) { 
                transition(to: .downswing)
            }
            
        case .downswing:
            DispatchQueue.main.async { self.statusMessage = "Downswing!" }
            // Store landmarks for replay
            let frame = SwingFrame(timestamp: Date().timeIntervalSince1970 - swingStartTime, landmarks: landmarks)
            swingLandmarks.append(frame)
            
            // Detect finish - wrist returns near baseline or steadies
            if avgWristY > (baselineWristY - 0.03) || isSteady {
                // Store final frame
                let finalFrame = SwingFrame(timestamp: Date().timeIntervalSince1970 - swingStartTime, landmarks: landmarks)
                swingLandmarks.append(finalFrame)
                
                transition(to: .finish)
                onVisualSwingDetected?()
                // Note: Don't auto-reset - ReplayView will handle this
            }
            
        case .impact:
            break
        }
        
        lastWristY = avgWristY
    }
    
    /// Validates that the person is in a golf address stance
    private func validateGolfStance(
        leftShoulder: NormalizedLandmark,
        rightShoulder: NormalizedLandmark,
        leftWrist: NormalizedLandmark,
        rightWrist: NormalizedLandmark,
        leftHip: NormalizedLandmark,
        rightHip: NormalizedLandmark
    ) -> Bool {
        // 1. Wrists should be close together (holding club)
        let wristDistance = sqrt(pow(leftWrist.x - rightWrist.x, 2) + pow(leftWrist.y - rightWrist.y, 2))
        let wristsClose = wristDistance < 0.25 // Max 25% of frame width apart
        
        // 2. Wrists should be below shoulders (arms extended down)
        let avgWristY = (leftWrist.y + rightWrist.y) / 2
        let avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let wristsBelowShoulders = avgWristY > avgShoulderY + 0.05
        
        // 3. Shoulders should show some forward lean (common in golf stance)
        // This is approximated by shoulder-hip distance being reasonable
        let avgHipY = (leftHip.y + rightHip.y) / 2
        let torsoLength = avgHipY - avgShoulderY
        let reasonableTorso = torsoLength > 0.15 && torsoLength < 0.5
        
        return wristsClose && wristsBelowShoulders && reasonableTorso
    }
    
    private func resetAddressProgress() {
        if addressConfidence > 0 {
            addressConfidence = max(0, addressConfidence - 1)
        }
        wristYHistory.removeAll()
        shoulderYHistory.removeAll()
    }
    
    private func transition(to newState: SwingState) {
        let oldState = state
        DispatchQueue.main.async {
            self.state = newState
            let emoji: String
            switch newState {
            case .idle: emoji = "⏸️"
            case .address: emoji = "🎯"
            case .backswing: emoji = "⬆️"
            case .downswing: emoji = "⬇️"
            case .impact: emoji = "💥"
            case .finish: emoji = "🏁"
            }
            print("\(emoji) SWING STAGE: \(oldState) → \(newState)")
        }
    }
    
    /// Called by ReplayView after replay completes to reset for next swing
    func resetToIdle() {
        swingLandmarks.removeAll()
        transition(to: .idle)
    }
}
