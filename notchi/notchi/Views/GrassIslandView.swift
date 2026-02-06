import SwiftUI

struct GrassIslandView: View {
    let sessions: [SessionData]

    private let patchWidth: CGFloat = 80
    private let spriteSpreadWidth: CGFloat = 0.7
    private let spriteLeftMargin: CGFloat = 0.15
    private let spriteJitterFactor: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(0..<patchCount(for: geometry.size.width), id: \.self) { _ in
                        Image("GrassIsland")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: patchWidth, height: geometry.size.height)
                            .clipped()
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)

                if sessions.isEmpty {
                    GrassSpriteView(state: .idle, xPosition: 0.5, totalWidth: geometry.size.width)
                } else {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        GrassSpriteView(
                            state: session.state,
                            xPosition: spritePosition(for: session.id, index: index, total: sessions.count),
                            totalWidth: geometry.size.width
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
    }

    private func patchCount(for width: CGFloat) -> Int {
        Int(ceil(width / patchWidth)) + 1
    }

    private func spritePosition(for sessionId: String, index: Int, total: Int) -> CGFloat {
        let segmentWidth = spriteSpreadWidth / CGFloat(max(total, 1))
        let basePosition = spriteLeftMargin + (CGFloat(index) * segmentWidth)
        let hash = abs(sessionId.hashValue)
        let jitter = CGFloat(hash % 100) / 100.0 * segmentWidth * spriteJitterFactor
        return basePosition + jitter
    }
}

private struct GrassSpriteView: View {
    let state: NotchiState
    let xPosition: CGFloat
    let totalWidth: CGFloat

    @State private var isSwayingRight = true
    @State private var isBobUp = true

    private let spriteSize: CGFloat = 64
    private let spriteYOffset: CGFloat = -15
    private let swayDuration: Double = 2.0

    var body: some View {
        SpriteSheetView(
            spriteSheet: state.spriteSheetName,
            frameCount: state.frameCount,
            fps: state.animationFPS,
            isAnimating: true
        )
        .frame(width: spriteSize, height: spriteSize)
        .rotationEffect(.degrees(isSwayingRight ? state.swayAmplitude : -state.swayAmplitude))
        .offset(x: xOffset, y: spriteYOffset + (isBobUp ? -2 : 2))
        .onAppear {
            startSwayAnimation()
            startBobAnimation()
        }
        .onChange(of: state) { _, _ in
            startBobAnimation()
        }
    }

    private var xOffset: CGFloat {
        let usableWidth = totalWidth * 0.8
        let leftMargin = totalWidth * 0.1
        return leftMargin + (xPosition * usableWidth) - (totalWidth / 2)
    }

    private func startSwayAnimation() {
        withAnimation(.easeInOut(duration: swayDuration).repeatForever(autoreverses: true)) {
            isSwayingRight.toggle()
        }
    }

    private func startBobAnimation() {
        withAnimation(.easeInOut(duration: state.bobDuration).repeatForever(autoreverses: true)) {
            isBobUp.toggle()
        }
    }
}
