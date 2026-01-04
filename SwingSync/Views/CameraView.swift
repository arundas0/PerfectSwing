import SwiftUI
import AVFoundation
import Combine
import Photos

struct CameraView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var poseDetector = PoseDetector()
    @StateObject private var swingLogic = SwingLogic()
    
    // Ring Buffer (not observed for View updates, but used)
    private let ringBuffer = RingBuffer()
    
    @State private var showingSaveSheet = false
    @State private var savedVideoURL: URL?
    
    // Timer to force UI refresh
    let refreshTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var refreshTick = 0
    
    var body: some View {
        ZStack {
            // Invisible view that changes to trigger refresh
            Text("\(refreshTick)").hidden()
            
            // Camera Layer
            CameraPreview(session: cameraService.session)
                .ignoresSafeArea()
            
            // Skeleton Overlay
            GeometryReader { geometry in
                SkeletonOverlay(landmarks: poseDetector.landmarks.first ?? [], geometry: geometry)
            }
            .allowsHitTesting(false)
            
            // Status Overlay
            VStack {
                // Status Text
                VStack(spacing: 12) {
                    Text(swingLogic.statusMessage)
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                    
                    // Debug Panel
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🎥 PIPELINE DEBUG")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        
                        HStack {
                            Text("Camera:")
                            Spacer()
                            Text(cameraService.isRunning ? "RUNNING" : "STOPPED")
                                .foregroundColor(cameraService.isRunning ? .green : .red)
                                .fontWeight(.bold)
                        }
                        
                        HStack {
                            Text("Frames:")
                            Spacer()
                            Text("\(poseDetector.framesReceived)")
                                .foregroundColor(poseDetector.framesReceived > 0 ? .green : .red)
                        }
                        
                        HStack {
                            Text("Detections:")
                            Spacer()
                            Text("\(poseDetector.detectionsAttempted)")
                                .foregroundColor(poseDetector.detectionsAttempted > 0 ? .green : .red)
                        }
                        
                        HStack {
                            Text("Results:")
                            Spacer()
                            Text("\(poseDetector.resultsReceived)")
                                .foregroundColor(poseDetector.resultsReceived > 0 ? .green : .red)
                        }
                        
                        HStack {
                            Text("Status:")
                            Spacer()
                            Text(poseDetector.lastError)
                                .foregroundColor(poseDetector.lastError == "✓ OK" ? .green : .orange)
                        }
                        
                        Divider().background(Color.white.opacity(0.3))
                        
                        HStack {
                            Text("Confidence:")
                            Spacer()
                            Text(swingLogic.debugInfo)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .frame(maxWidth: 300)
                }
                .padding(.top, 50)
                
                Spacer()
            }
            
            if !cameraService.isAuthorized {
                Text("Camera permission required")
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
            }
        }
        .fullScreenCover(isPresented: $showingSaveSheet) {
            SwingSavedView(videoURL: savedVideoURL) {
                showingSaveSheet = false
            }
        }
        .onAppear {
            cameraService.delegate = poseDetector
            poseDetector.onFrame = { [self] sampleBuffer in
                // Feed frames to ring buffer for video capture
                ringBuffer.append(sampleBuffer)
            }
            poseDetector.onLandmarks = { landmarks in
                swingLogic.process(landmarks: landmarks)
            }
            
            swingLogic.onVisualSwingDetected = {
                print("🎬 SWING DETECTED - Triggering save...")
                saveSwing()
            }
            
            cameraService.start()
        }
        .onReceive(refreshTimer) { _ in
            // Force SwiftUI to re-evaluate view by changing state
            refreshTick += 1
        }
        .onDisappear {
            cameraService.stop()
        }
    }
    
    private func saveSwing() {
        // Create user-friendly filename with date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM-dd-yyyy_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "GolfSwing_\(dateString).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        print("💾 Attempting to save swing to: \(url)")
        
        ringBuffer.save(to: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedUrl):
                    self.savedVideoURL = savedUrl
                    self.showingSaveSheet = true
                    print("✅ Saved swing to: \(savedUrl)")
                case .failure(let error):
                    print("❌ Failed to save swing: \(error)")
                }
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // Apply rotation when connection becomes available
        if let connection = uiView.videoPreviewLayer.connection {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
}

class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
