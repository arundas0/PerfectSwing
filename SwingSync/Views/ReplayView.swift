import SwiftUI
import MediaPipeTasksVision

/// Displays an animated replay of the swing skeleton at 0.6x speed
struct ReplayView: View {
    let swingFrames: [SwingLogic.SwingFrame]
    let onReplayComplete: () -> Void
    
    /// Which body segment to highlight
    enum HighlightSegment: CaseIterable {
        case hips
        case shoulders
        case head
    }
    
    @State private var currentFrameIndex = 0
    @State private var isPlaying = false
    @State private var highlightSegment: HighlightSegment = .hips
    
    // Playback speed (0.6x means 1.67x slower)
    private let playbackSpeed: Double = 0.6
    private let frameRate: Double = 30 // Approximate capture frame rate
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    Text("Analyzing Your Swing")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.top, 60)
                    
                    Text("Watching: \(highlightSegment.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    // Skeleton replay area
                    ZStack {
                        // Background frame
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.3))
                            .frame(height: geometry.size.height * 0.5)
                        
                        // Skeleton animation
                        if currentFrameIndex < swingFrames.count {
                            ReplaySkeletonView(
                                landmarks: swingFrames[currentFrameIndex].landmarks,
                                highlightSegment: highlightSegment,
                                size: CGSize(
                                    width: geometry.size.width - 40,
                                    height: geometry.size.height * 0.5
                                )
                            )
                        }
                        
                        // Frame counter
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("\(currentFrameIndex + 1)/\(swingFrames.count)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(8)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Progress bar
                    GeometryReader { barGeometry in
                        ZStack(alignment: .leading) {
                            // Background
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)
                            
                            // Progress
                            Capsule()
                                .fill(Color.green)
                                .frame(
                                    width: swingFrames.isEmpty ? 0 : 
                                        barGeometry.size.width * CGFloat(currentFrameIndex + 1) / CGFloat(swingFrames.count),
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 40)
                    
                    Text("0.6x Speed")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    // Skip button
                    Button(action: {
                        onReplayComplete()
                    }) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            startReplay()
        }
    }
    
    private func startReplay() {
        guard !swingFrames.isEmpty else {
            print("⚠️ ReplayView: No frames to replay")
            onReplayComplete()
            return
        }
        
        print("🎬 ReplayView: Starting replay of \(swingFrames.count) frames")
        
        // Randomly select a highlight segment
        highlightSegment = HighlightSegment.allCases.randomElement() ?? .hips
        
        isPlaying = true
        currentFrameIndex = 0
        
        // Calculate interval between frames (slowed down)
        let baseInterval = 1.0 / frameRate
        let slowedInterval = baseInterval / playbackSpeed
        
        // Animate through frames
        animateNextFrame(interval: slowedInterval)
    }
    
    private func animateNextFrame(interval: TimeInterval) {
        guard isPlaying else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            if currentFrameIndex < swingFrames.count - 1 {
                currentFrameIndex += 1
                animateNextFrame(interval: interval)
            } else {
                // Replay complete - pause briefly then transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🎬 ReplayView: Replay complete")
                    onReplayComplete()
                }
            }
        }
    }
}

/// The skeleton view with highlighting for replay
struct ReplaySkeletonView: View {
    let landmarks: [NormalizedLandmark]
    let highlightSegment: ReplayView.HighlightSegment
    let size: CGSize
    
    // Skeleton connections
    private let connections: [(Int, Int)] = [
        (11, 13), (13, 15), // Left Arm
        (12, 14), (14, 16), // Right Arm
        (11, 12), (23, 24), // Torso horizontal
        (11, 23), (12, 24), // Torso vertical
        (23, 25), (25, 27), // Left Leg
        (24, 26), (26, 28)  // Right Leg
    ]
    
    // Landmark indices for each segment
    private var highlightedIndices: Set<Int> {
        switch highlightSegment {
        case .hips:
            return Set([23, 24, 25, 26]) // Hips and upper legs
        case .shoulders:
            return Set([11, 12, 13, 14]) // Shoulders and upper arms
        case .head:
            return Set([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) // Face landmarks
        }
    }
    
    var body: some View {
        ZStack {
            // Draw lines
            Path { path in
                for (startIdx, endIdx) in connections {
                    guard startIdx < landmarks.count, endIdx < landmarks.count else { continue }
                    
                    let startPoint = point(for: landmarks[startIdx])
                    let endPoint = point(for: landmarks[endIdx])
                    
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 2)
            
            // Draw highlighted connections
            Path { path in
                for (startIdx, endIdx) in connections {
                    guard startIdx < landmarks.count, endIdx < landmarks.count else { continue }
                    
                    // Only draw if both points are in highlighted segment
                    if highlightedIndices.contains(startIdx) || highlightedIndices.contains(endIdx) {
                        let startPoint = point(for: landmarks[startIdx])
                        let endPoint = point(for: landmarks[endIdx])
                        
                        path.move(to: startPoint)
                        path.addLine(to: endPoint)
                    }
                }
            }
            .stroke(Color.green, lineWidth: 4)
            
            // Draw points
            ForEach(0..<min(landmarks.count, 33), id: \.self) { index in
                let p = point(for: landmarks[index])
                let isHighlighted = highlightedIndices.contains(index)
                
                Circle()
                    .fill(isHighlighted ? Color.green : Color.white.opacity(0.4))
                    .frame(width: isHighlighted ? 10 : 6, height: isHighlighted ? 10 : 6)
                    .position(p)
            }
        }
        .frame(width: size.width, height: size.height)
    }
    
    private func point(for landmark: NormalizedLandmark) -> CGPoint {
        // Convert normalized coordinates to view coordinates
        // X is already correct since video is mirrored
        return CGPoint(
            x: CGFloat(landmark.x) * size.width,
            y: CGFloat(landmark.y) * size.height
        )
    }
}

extension ReplayView.HighlightSegment {
    var displayName: String {
        switch self {
        case .hips: return "Hip Movement"
        case .shoulders: return "Shoulder Rotation"
        case .head: return "Head Position"
        }
    }
}

#Preview {
    ReplayView(swingFrames: [], onReplayComplete: {})
}
