import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
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
                
                VStack {
                    Image(systemName: "figure.golf")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("SwingSync")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                        
                    Text("The AI Golf Coach")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.2)) {
                        self.size = 1.0
                        self.opacity = 1.0
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
