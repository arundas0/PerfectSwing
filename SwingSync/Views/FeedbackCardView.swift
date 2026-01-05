import SwiftUI

/// Slide-up feedback card showing the "Next Fix" for the golfer
struct FeedbackCardView: View {
    let feedback: SwingAnalyzer.SwingFeedback
    let onDismiss: () -> Void
    
    @State private var cardOffset: CGFloat = 300
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Card container
            VStack(spacing: 20) {
                // Handle indicator
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                
                // Segment icon
                ZStack {
                    Circle()
                        .fill(segmentColor.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: segmentIcon)
                        .font(.system(size: 28))
                        .foregroundColor(segmentColor)
                }
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.5)
                
                // Title
                Text(feedback.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                
                // Instruction
                Text(feedback.instruction)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                
                // Confidence indicator
                HStack(spacing: 6) {
                    Text("Confidence:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Dots
                    ForEach(0..<10, id: \.self) { index in
                        Circle()
                            .fill(index < feedback.confidence ? segmentColor : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                    
                    Text("\(feedback.confidence)/10")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(showContent ? 1 : 0)
                .padding(.top, 8)
                
                // Continue button
                Button(action: onDismiss) {
                    Text("Got it!")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .opacity(showContent ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "2d3436"), Color(hex: "1e272e")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .offset(y: cardOffset)
        }
        .ignoresSafeArea()
        .onAppear {
            // Slide up animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                cardOffset = 0
            }
            
            // Content fade in
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                showContent = true
            }
        }
    }
    
    private var segmentColor: Color {
        switch feedback.segment {
        case .hips: return .orange
        case .shoulders: return .blue
        case .head: return .purple
        case .arms: return .green
        case .general: return .cyan
        }
    }
    
    private var segmentIcon: String {
        switch feedback.segment {
        case .hips: return "figure.stand"
        case .shoulders: return "figure.arms.open"
        case .head: return "brain.head.profile"
        case .arms: return "hand.raised"
        case .general: return "figure.golf"
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        FeedbackCardView(
            feedback: SwingAnalyzer.SwingFeedback(
                title: "Hip sway detected",
                instruction: "Try keeping your hips centered over your feet throughout the swing.",
                confidence: 8,
                segment: .hips
            ),
            onDismiss: {}
        )
    }
}
