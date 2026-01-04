import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    @State private var loadingStatus = "Initializing..."
    @State private var progress = 0.0
    
    var body: some View {
        if isActive {
            CameraView()
        } else {
            ZStack {
                // background
                LinearGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.8), Color.blue.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Image(systemName: "figure.golf")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("SwingSync")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        
                    Text("The AI Golf Coach")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Loading Status
                    VStack(spacing: 12) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .frame(width: 200)
                        
                        Text(loadingStatus)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .frame(height: 20)
                    }
                    .padding(.top, 20)
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.2)) {
                        self.size = 1.0
                        self.opacity = 1.0
                    }
                    
                    // Simulate loading stages
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        loadingStatus = "Loading AI Model..."
                        progress = 0.33
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        loadingStatus = "Initializing Camera..."
                        progress = 0.66
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        loadingStatus = "Ready!"
                        progress = 1.0
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}
