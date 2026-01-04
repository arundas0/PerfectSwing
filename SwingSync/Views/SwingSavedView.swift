import SwiftUI
import Photos

struct SwingSavedView: View {
    let videoURL: URL?
    let onDismiss: () -> Void
    
    @State private var savedToPhotos = false
    @State private var saveError: String?
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Success animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.5 : 1.0)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .green.opacity(0.5), radius: 20)
                
                Image(systemName: savedToPhotos ? "checkmark" : "figure.golf")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text(savedToPhotos ? "Swing Saved! 🎉" : "Great Swing!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                if savedToPhotos {
                    Text("Saved to your Photo Library")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                } else if let error = saveError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Saving to Photos...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                Text(savedToPhotos ? "Continue" : "Dismiss")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            saveToPhotosLibrary()
        }
    }
    
    private func saveToPhotosLibrary() {
        guard let url = videoURL else {
            saveError = "No video to save"
            return
        }
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized || status == .limited {
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: url, options: nil)
                    
                    // Set creation date for proper sorting
                    request.creationDate = Date()
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            savedToPhotos = true
                            isAnimating = false
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: url)
                            print("✅ Saved to Photos Library")
                        } else {
                            saveError = error?.localizedDescription ?? "Failed to save"
                            print("❌ Photos save error: \(String(describing: error))")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    saveError = "Please allow Photos access in Settings"
                }
            }
        }
    }
}

// Color extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    SwingSavedView(videoURL: nil, onDismiss: {})
}
