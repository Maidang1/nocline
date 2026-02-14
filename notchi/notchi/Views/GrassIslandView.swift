import SwiftUI

private enum SpriteLayout {
    static let size: CGFloat = 64
    static let usableWidthFraction: CGFloat = 0.8
    static let leftMarginFraction: CGFloat = 0.1

    static func xOffset(xPosition: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let usableWidth = totalWidth * usableWidthFraction
        let leftMargin = totalWidth * leftMarginFraction
        return leftMargin + (xPosition * usableWidth) - (totalWidth / 2)
    }

    static func depthSorted(_ sessions: [SessionData]) -> [SessionData] {
        sessions.sorted { $0.spriteYOffset < $1.spriteYOffset }
    }
}

// MARK: - Visual layer (placed in .background, no interaction)

struct GrassIslandView: View {
    let sessions: [SessionData]

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
                .drawingGroup()

                if sessions.isEmpty {
                    GrassSpriteView(state: .idle, xPosition: 0.5, yOffset: -15, totalWidth: geometry.size.width)
                } else {
                    ForEach(SpriteLayout.depthSorted(sessions)) { session in
                        GrassSpriteView(
                            state: session.state,
                            xPosition: session.spriteXPosition,
                            yOffset: session.spriteYOffset,
                            totalWidth: geometry.size.width
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private func patchCount(for width: CGFloat) -> Int {
        Int(ceil(width / patchWidth)) + 1
    }
}

// MARK: - Interaction layer (placed in .overlay for reliable hit testing)

struct GrassTapOverlay: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    var onSelectSession: ((String) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.clear

                if !sessions.isEmpty {
                    ForEach(SpriteLayout.depthSorted(sessions)) { session in
                        SpriteTapTarget(
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
    }
}

// MARK: - Private views

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct SpriteTapTarget: View {
    let isSelected: Bool
    let xPosition: CGFloat
    let yOffset: CGFloat
    let totalWidth: CGFloat
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var tapScale: CGFloat = 1.0

    private let glowColor = Color(red: 0.4, green: 0.7, blue: 1.0)

    private var glowOpacity: Double {
        if isSelected { return 0.7 }
        if isHovered { return 0.3 }
        return 0
    }

    var body: some View {
        Button(action: handleTap) {
            Color.clear
                .frame(width: SpriteLayout.size, height: SpriteLayout.size)
                .contentShape(Rectangle())
                .background(alignment: .bottom) {
                    if glowOpacity > 0 {
                        Ellipse()
                            .fill(glowColor.opacity(glowOpacity))
                            .frame(width: SpriteLayout.size * 0.85, height: SpriteLayout.size * 0.25)
                            .blur(radius: 8)
                            .offset(y: 4)
                    }
                }
        }
        .buttonStyle(NoHighlightButtonStyle())
        .onHover { isHovered = $0 }
        .scaleEffect(tapScale)
        .offset(x: SpriteLayout.xOffset(xPosition: xPosition, totalWidth: totalWidth), y: yOffset)
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

private struct GrassSpriteView: View {
    let state: NotchiState
    let xPosition: CGFloat
    let yOffset: CGFloat
    let totalWidth: CGFloat

    @State private var isSwayingRight = true
    @State private var isBobUp = true

    private let swayDuration: Double = 2.0
    private let bobAmplitude: CGFloat = 2

    var body: some View {
        SpriteSheetView(
            spriteSheet: state.spriteSheetName,
            frameCount: state.frameCount,
            columns: state.columns,
            fps: state.animationFPS,
            isAnimating: true
        )
        .frame(width: SpriteLayout.size, height: SpriteLayout.size)
        .rotationEffect(.degrees(isSwayingRight ? state.swayAmplitude : -state.swayAmplitude), anchor: .bottom)
        .offset(x: SpriteLayout.xOffset(xPosition: xPosition, totalWidth: totalWidth), y: yOffset + (isBobUp ? -bobAmplitude : bobAmplitude))
        .onAppear {
            startSwayAnimation()
            startBobAnimation()
        }
        .onChange(of: state) {
            startBobAnimation()
        }
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
