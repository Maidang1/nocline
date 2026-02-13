import SwiftUI

struct GrassIslandView: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    var onSelectSession: ((String) -> Void)?

    private let patchWidth: CGFloat = 80

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
                    GrassSpriteView(state: .idle, xPosition: 0.5, yOffset: -15, totalWidth: geometry.size.width)
                } else {
                    // Sorted far-to-near so closer sprites paint on top
                    ForEach(depthSortedSessions) { session in
                        GrassSpriteView(
                            state: session.state,
                            isSelected: session.id == selectedSessionId,
                            xPosition: session.spriteXPosition,
                            yOffset: session.spriteYOffset,
                            totalWidth: geometry.size.width,
                            onTap: { onSelectSession?(session.id) }
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
    }

    private var depthSortedSessions: [SessionData] {
        sessions.sorted { $0.spriteYOffset < $1.spriteYOffset }
    }

    private func patchCount(for width: CGFloat) -> Int {
        Int(ceil(width / patchWidth)) + 1
    }
}

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct GrassSpriteView: View {
    let state: NotchiState
    var isSelected: Bool = false
    let xPosition: CGFloat
    let yOffset: CGFloat
    let totalWidth: CGFloat
    var onTap: (() -> Void)?

    @State private var isSwayingRight = true
    @State private var isBobUp = true
    @State private var isHovered = false
    @State private var tapScale: CGFloat = 1.0

    private let spriteSize: CGFloat = 64
    private let swayDuration: Double = 2.0
    private let bobAmplitude: CGFloat = 2

    // Must match SessionData's xPositionMin/xPositionRange contract
    private let usableWidthFraction: CGFloat = 0.8
    private let leftMarginFraction: CGFloat = 0.1

    private let glowColor = Color(red: 0.4, green: 0.7, blue: 1.0)

    private var glowOpacity: Double {
        if isSelected { return 0.7 }
        if isHovered { return 0.3 }
        return 0
    }

    var body: some View {
        Button(action: handleTap) {
            SpriteSheetView(
                spriteSheet: state.spriteSheetName,
                frameCount: state.frameCount,
                columns: state.columns,
                fps: state.animationFPS,
                isAnimating: true
            )
            .frame(width: spriteSize, height: spriteSize)
            .background(alignment: .bottom) {
                if glowOpacity > 0 {
                    Ellipse()
                        .fill(glowColor.opacity(glowOpacity))
                        .frame(width: spriteSize * 0.85, height: spriteSize * 0.25)
                        .blur(radius: 8)
                        .offset(y: 4)
                }
            }
        }
        .buttonStyle(NoHighlightButtonStyle())
        .onHover { isHovered = $0 }
        .scaleEffect(tapScale)
        .rotationEffect(.degrees(isSwayingRight ? state.swayAmplitude : -state.swayAmplitude), anchor: .bottom)
        .offset(x: xOffset, y: yOffset + (isBobUp ? -bobAmplitude : bobAmplitude))
        .onAppear {
            startSwayAnimation()
            startBobAnimation()
        }
        .onChange(of: state) {
            startBobAnimation()
        }
    }

    private var xOffset: CGFloat {
        let usableWidth = totalWidth * usableWidthFraction
        let leftMargin = totalWidth * leftMarginFraction
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

    private func handleTap() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { tapScale = 1.15 }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { tapScale = 1.0 }
        }
        onTap?()
    }
}
