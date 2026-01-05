import Foundation
import MediaPipeTasksVision

/// Analyzes swing landmarks to provide feedback
class SwingAnalyzer {
    
    /// A single piece of feedback with confidence
    struct SwingFeedback {
        let title: String           // Plain language issue
        let instruction: String     // What to try
        let confidence: Int         // 1-10 confidence score
        let segment: FeedbackSegment
        
        enum FeedbackSegment {
            case hips
            case shoulders
            case head
            case arms
            case general
        }
    }
    
    /// Analyze swing frames and return the most important feedback
    func analyze(frames: [SwingLogic.SwingFrame]) -> SwingFeedback? {
        guard frames.count > 5 else { return nil }
        
        var issues: [SwingFeedback] = []
        
        // Analyze different aspects
        if let hipIssue = analyzeHipMovement(frames: frames) {
            issues.append(hipIssue)
        }
        
        if let headIssue = analyzeHeadMovement(frames: frames) {
            issues.append(headIssue)
        }
        
        if let shoulderIssue = analyzeShoulderRotation(frames: frames) {
            issues.append(shoulderIssue)
        }
        
        if let tempoIssue = analyzeSwingTempo(frames: frames) {
            issues.append(tempoIssue)
        }
        
        // Return highest confidence issue, or a general tip
        if let topIssue = issues.max(by: { $0.confidence < $1.confidence }) {
            return topIssue
        }
        
        // Default feedback if nothing specific detected
        return SwingFeedback(
            title: "Good swing tempo!",
            instruction: "Focus on a smooth takeaway to maintain this rhythm.",
            confidence: 5,
            segment: .general
        )
    }
    
    // MARK: - Analysis Methods
    
    private func analyzeHipMovement(frames: [SwingLogic.SwingFrame]) -> SwingFeedback? {
        // Check lateral hip sway (X movement)
        guard let firstFrame = frames.first,
              let midFrame = frames[safe: frames.count / 2],
              firstFrame.landmarks.count > 24,
              midFrame.landmarks.count > 24 else { return nil }
        
        let leftHip = 23
        let rightHip = 24
        
        // Calculate hip center at start vs mid-swing
        let startHipX = (firstFrame.landmarks[leftHip].x + firstFrame.landmarks[rightHip].x) / 2
        let midHipX = (midFrame.landmarks[leftHip].x + midFrame.landmarks[rightHip].x) / 2
        
        let lateralSway = abs(midHipX - startHipX)
        
        // Threshold: more than 8% of frame width is excessive
        if lateralSway > 0.08 {
            let swayDirection = midHipX > startHipX ? "right" : "left"
            return SwingFeedback(
                title: "Hip sway detected",
                instruction: "Try keeping your hips centered over your feet throughout the swing.",
                confidence: Int(min(10, lateralSway * 100)),
                segment: .hips
            )
        }
        
        return nil
    }
    
    private func analyzeHeadMovement(frames: [SwingLogic.SwingFrame]) -> SwingFeedback? {
        // Check if head stays still during swing
        guard frames.count > 3 else { return nil }
        
        let noseIndex = 0
        
        var minY: Float = 1.0
        var maxY: Float = 0.0
        var minX: Float = 1.0
        var maxX: Float = 0.0
        
        for frame in frames {
            guard frame.landmarks.count > noseIndex else { continue }
            let nose = frame.landmarks[noseIndex]
            minY = min(minY, nose.y)
            maxY = max(maxY, nose.y)
            minX = min(minX, nose.x)
            maxX = max(maxX, nose.x)
        }
        
        let verticalMovement = maxY - minY
        let horizontalMovement = maxX - minX
        
        // Head should move less than 5% vertically
        if verticalMovement > 0.05 {
            return SwingFeedback(
                title: "Head lifting during swing",
                instruction: "Keep your eye on the ball and maintain a steady head position.",
                confidence: Int(min(10, verticalMovement * 150)),
                segment: .head
            )
        }
        
        // Head should move less than 8% horizontally  
        if horizontalMovement > 0.08 {
            return SwingFeedback(
                title: "Head moving laterally",
                instruction: "Focus on rotating around your spine while keeping your head stable.",
                confidence: Int(min(10, horizontalMovement * 100)),
                segment: .head
            )
        }
        
        return nil
    }
    
    private func analyzeShoulderRotation(frames: [SwingLogic.SwingFrame]) -> SwingFeedback? {
        // Analyze shoulder turn during backswing
        guard let firstFrame = frames.first,
              let topFrame = findTopOfBackswing(frames: frames),
              firstFrame.landmarks.count > 12,
              topFrame.landmarks.count > 12 else { return nil }
        
        let leftShoulder = 11
        let rightShoulder = 12
        
        // Calculate shoulder line angle at address vs top
        let startAngle = shoulderAngle(frame: firstFrame)
        let topAngle = shoulderAngle(frame: topFrame)
        
        let rotation = abs(topAngle - startAngle)
        
        // Good shoulder turn is 45-90 degrees (in normalized coords, roughly 0.1 - 0.2)
        if rotation < 0.05 {
            return SwingFeedback(
                title: "Limited shoulder turn",
                instruction: "Try rotating your shoulders more on the backswing for increased power.",
                confidence: 7,
                segment: .shoulders
            )
        }
        
        return nil
    }
    
    private func analyzeSwingTempo(frames: [SwingLogic.SwingFrame]) -> SwingFeedback? {
        guard frames.count > 2,
              let first = frames.first,
              let last = frames.last else { return nil }
        
        let duration = last.timestamp - first.timestamp
        
        // Ideal swing is 0.8 - 1.5 seconds
        if duration < 0.5 {
            return SwingFeedback(
                title: "Swing too fast",
                instruction: "Slow down your takeaway for better control and timing.",
                confidence: 8,
                segment: .general
            )
        }
        
        if duration > 2.0 {
            return SwingFeedback(
                title: "Swing tempo slow",
                instruction: "Try a more connected, fluid motion through the ball.",
                confidence: 6,
                segment: .general
            )
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func findTopOfBackswing(frames: [SwingLogic.SwingFrame]) -> SwingLogic.SwingFrame? {
        // Find frame where left wrist (15) is highest (lowest Y value)
        let wristIndex = 15
        var topFrame: SwingLogic.SwingFrame?
        var lowestY: Float = 1.0
        
        for frame in frames {
            guard frame.landmarks.count > wristIndex else { continue }
            let wristY = frame.landmarks[wristIndex].y
            if wristY < lowestY {
                lowestY = wristY
                topFrame = frame
            }
        }
        
        return topFrame
    }
    
    private func shoulderAngle(frame: SwingLogic.SwingFrame) -> Float {
        guard frame.landmarks.count > 12 else { return 0 }
        let left = frame.landmarks[11]
        let right = frame.landmarks[12]
        // Simple angle approximation using X difference
        return right.x - left.x
    }
}

// Safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
