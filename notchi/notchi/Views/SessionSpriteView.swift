import SwiftUI

struct SessionSpriteView: View {
    let state: NotchiState
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isBobUp = false

    private var bobAmplitude: CGFloat {
        isSelected ? state.bobAmplitude : state.bobAmplitude * 0.67
    }

    var body: some View {
        Button(action: onTap) {
            SpriteSheetView(
                spriteSheet: state.spriteSheetName,
                frameCount: state.frameCount,
                columns: state.columns,
                fps: state.animationFPS,
                isAnimating: true
            )
            .frame(width: 30, height: 30)
            .opacity(isSelected ? 1.0 : 0.5)
            .offset(y: isBobUp ? -bobAmplitude : bobAmplitude)
        }
        .buttonStyle(.plain)
        .onAppear {
            startBobAnimation()
        }
        .onChange(of: state) {
            startBobAnimation()
        }
    }

    private func startBobAnimation() {
        if bobAmplitude == 0 {
            withAnimation(.easeInOut(duration: 0.3)) { isBobUp = false }
            return
        }
        withAnimation(.easeInOut(duration: state.bobDuration).repeatForever(autoreverses: true)) {
            isBobUp.toggle()
        }
    }
}
