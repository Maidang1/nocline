import SwiftUI

struct GrassIslandView: View {
    let state: NotchiState

    @State private var spriteXPosition: CGFloat = 0.5
    @State private var isSwayingRight = true
    @State private var isBobUp = true
    @State private var isWalking = false
    @State private var facingRight = true

    private let patchWidth: CGFloat = 80
    private let spriteSize: CGFloat = 32
    private let spriteYOffset: CGFloat = -15
    private let swayDuration: Double = 2.0
    private let walkDuration: Double = 1.5

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

                spriteView
                    .offset(x: spriteXOffset(for: geometry.size.width), y: spriteYOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
        .onAppear {
            startSwayAnimation()
            startBobAnimation()
            scheduleNextWalk()
        }
        .onChange(of: state) { _, _ in
            startBobAnimation()
        }
    }

    private func patchCount(for width: CGFloat) -> Int {
        Int(ceil(width / patchWidth)) + 1
    }

    private var spriteView: some View {
        Image(systemName: state.sfSymbolName)
            .font(.system(size: spriteSize))
            .foregroundColor(.white)
            .scaleEffect(x: facingRight ? 1 : -1, y: 1)
            .rotationEffect(.degrees(isSwayingRight ? state.swayAmplitude : -state.swayAmplitude))
            .offset(y: isBobUp ? -2 : 2)
    }

    private func spriteXOffset(for totalWidth: CGFloat) -> CGFloat {
        let usableWidth = totalWidth * 0.8
        let leftMargin = totalWidth * 0.1
        return leftMargin + (spriteXPosition * usableWidth) - (totalWidth / 2)
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

    private func scheduleNextWalk() {
        guard state.canWalk else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                scheduleNextWalk()
            }
            return
        }

        let interval = Double.random(in: state.walkFrequencyRange)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            performWalk()
        }
    }

    private func performWalk() {
        guard state.canWalk, !isWalking else {
            scheduleNextWalk()
            return
        }

        isWalking = true

        let targetPosition = CGFloat.random(in: 0.15...0.85)
        let movingRight = targetPosition > spriteXPosition

        withAnimation(.easeInOut(duration: 0.1)) {
            facingRight = movingRight
        }

        withAnimation(.easeInOut(duration: walkDuration)) {
            spriteXPosition = targetPosition
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + walkDuration) {
            isWalking = false
            scheduleNextWalk()
        }
    }
}
