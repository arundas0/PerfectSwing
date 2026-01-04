import SwiftUI
import MediaPipeTasksVision

struct SkeletonOverlay: View {
    let landmarks: [NormalizedLandmark]
    let geometry: GeometryProxy
    
    // Simple connections for a basic skeleton (indices based on MediaPipe Pose topology)
    // 11-13 (Left Shoulder-Elbow), 13-15 (Left Elbow-Wrist)
    // 12-14 (Right Shoulder-Elbow), 14-16 (Right Elbow-Wrist)
    // 11-12 (Shoulders), 23-24 (Hips), 11-23 (Left Body), 12-24 (Right Body)
    // 23-25 (Left Hip-Knee), 25-27 (Left Knee-Ankle)
    // 24-26 (Right Hip-Knee), 26-28 (Right Knee-Ankle)
    private let connections: [(Int, Int)] = [
        (11, 13), (13, 15), // Left Arm
        (12, 14), (14, 16), // Right Arm
        (11, 12), (23, 24), // Torso horizontal
        (11, 23), (12, 24), // Torso vertical
        (23, 25), (25, 27), // Left Leg
        (24, 26), (26, 28)  // Right Leg
    ]
    
    var body: some View {
        ZStack {
            // Draw Lines
            Path { path in
                for (startIdx, endIdx) in connections {
                    guard startIdx < landmarks.count, endIdx < landmarks.count else { continue }
                    
                    let startPoint = point(for: landmarks[startIdx])
                    let endPoint = point(for: landmarks[endIdx])
                    
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                }
            }
            .stroke(Color.green, lineWidth: 3)
            
            // Draw Points
            ForEach(0..<landmarks.count, id: \.self) { index in
                // Only draw relevant landmarks (e.g., upper body + legs, skip face for now if desired, or draw all)
                // MediaPipe Pose has 33 landmarks.
                let p = point(for: landmarks[index])
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .position(p)
            }
        }
    }
    
    private func point(for landmark: NormalizedLandmark) -> CGPoint {
        // MediaPipe coordinates: x, y in [0, 1].
        // Video frames are already mirrored by CameraService, so landmarks
        // are in the correct mirrored space - no additional X inversion needed.
        
        return CGPoint(
            x: CGFloat(landmark.x) * geometry.size.width,
            y: CGFloat(landmark.y) * geometry.size.height
        )
    }
}
