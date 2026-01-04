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
    
    // Config
    private let addressDurationThreshold: TimeInterval = 0.5 // Was 1.5
    private let impactMotionThreshold: Double = 0.05
    
    // State
    // private var addressStartTime: Date? // REMOVED
    private var addressConfidence: Int = 0 
    private let addressThreshold = 15 // Approx 0.5s at 30fps
    
    private var lastWristY: Float = 0.0
    private var baselineWristY: Float = 0.0 
    private var previousLandmarks: [NormalizedLandmark]?
    
    // Callback
    var onVisualSwingDetected: (() -> Void)?
    
    private var processCount = 0
    
    // Positional Window for steadiness
    private var windowYHistory: [Float] = []
    private let windowSize = 10 
    private let steadyThreshold: Float = 0.18 // Increased to 0.18 based on user feedback of 0.16 jitter
    
    @Published var debugInfo: String = ""

    func process(landmarks: [NormalizedLandmark]) {
        processCount += 1
        
        // Check for basic visibility
        guard landmarks.count > 20 else {
            DispatchQueue.main.async {
                self.statusMessage = "Step into full view"
                self.debugInfo = "No golfer detected"
            }
            return 
        }
        
        let nose = landmarks[0]
        if (nose.visibility?.floatValue ?? 0.0) < 0.5 {
            if processCount % 10 == 0 {
                DispatchQueue.main.async {
                    self.statusMessage = "Center yourself in camera"
                }
            }
        }
        
        let wristY = landmarks[16].y 
        
        // Update history
        windowYHistory.append(wristY)
        if windowYHistory.count > windowSize {
            windowYHistory.removeFirst()
        }
        
        // Calculate window range
        let minY = windowYHistory.min() ?? 0
        let maxY = windowYHistory.max() ?? 0
        let range = maxY - minY
        let isSteadyInWindow = range < steadyThreshold
        
        // Update debug info every few frames
        if processCount % 3 == 0 {
            DispatchQueue.main.async {
                self.debugInfo = "Y: \(String(format: "%.3f", wristY)) Jitter: \(String(format: "%.3f", range)) (\(Int((range/self.steadyThreshold)*100))%)"
            }
        }
        
        switch state {
        case .idle, .finish:
            if isSteadyInWindow {
                addressConfidence += 1
                let progress = min(100, Int((Double(self.addressConfidence) / Double(self.addressThreshold)) * 100))
                DispatchQueue.main.async {
                    self.statusMessage = "Hold still... \(progress)%"
                }
                
                if addressConfidence >= addressThreshold {
                    baselineWristY = wristY
                    transition(to: .address)
                    addressConfidence = 0
                }
            } else {
                if addressConfidence > 0 {
                    addressConfidence = max(0, addressConfidence - 1)
                } else {
                    if processCount % 10 == 0 {
                        DispatchQueue.main.async {
                            self.statusMessage = range > 0.4 ? "Too much movement" : "Waiting for golfer..."
                        }
                    }
                }
            }
            
        case .address:
            DispatchQueue.main.async { self.statusMessage = "READY: Swing Now!" }
            if (baselineWristY - wristY) > 0.12 { 
                transition(to: .backswing)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    if self?.state == .backswing || self?.state == .downswing {
                        self?.transition(to: .finish)
                        self?.onVisualSwingDetected?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self?.transition(to: .idle)
                        }
                    }
                }
            }
            
        case .backswing:
             if wristY > (baselineWristY - 0.15) { 
                transition(to: .downswing)
             }
            
        case .downswing:
             if wristY > (baselineWristY - 0.05) || isSteadyInWindow {
                 transition(to: .finish)
                 onVisualSwingDetected?()
             }
            
        case .impact:
            break
        }
        
        lastWristY = wristY
    }
    
    private func transition(to newState: SwingState) {
        DispatchQueue.main.async {
            self.state = newState
            self.statusMessage = "State: \(newState)"
            print("Swing State: \(newState)")
        }
    }
}
