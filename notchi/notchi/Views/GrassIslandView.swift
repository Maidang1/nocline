import SwiftUI

private enum SpriteLayout {
    static let size: CGFloat = 60
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
    var selectedSessionId: String?
    var hoveredSessionId: String?
    var handoffSessionId: String?
    var handoffProgress: CGFloat = 1
    var isHandoffCollapsing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                stageBackground(for: geometry.size)

                if !sessions.isEmpty {
                    ForEach(SpriteLayout.depthSorted(sessions)) { session in
                        GrassSpriteView(
                            state: session.state,
                            xPosition: session.spriteXPosition,
                            yOffset: session.spriteYOffset,
                            totalWidth: geometry.size.width,
                            glowOpacity: glowOpacity(for: session.id)
                        )
                        .opacity(spriteOpacity(for: session.id))
                        .blur(radius: spriteBlur(for: session.id))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private func glowOpacity(for sessionId: String) -> Double {
        if sessionId == selectedSessionId { return 0.7 }
        if sessionId == hoveredSessionId { return 0.3 }
        return 0
    }

    private func spriteOpacity(for sessionId: String) -> Double {
        guard sessionId == handoffSessionId else { return 1 }
        return SpriteHandoffVisuals.opacity(
            for: handoffProgress,
            isSource: isHandoffCollapsing
        )
    }

    private func spriteBlur(for sessionId: String) -> CGFloat {
        guard sessionId == handoffSessionId else { return 0 }
        return SpriteHandoffVisuals.blur(
            for: handoffProgress,
            isSource: isHandoffCollapsing
        )
    }

    @ViewBuilder
    private func stageBackground(for size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(TerminalColors.shellBackground)
                .frame(width: size.width, height: size.height)

            LinearGradient(
                colors: [
                    TerminalColors.panelBackground.opacity(0.92),
                    TerminalColors.shellBackground.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)

            LinearGradient(
                colors: [
                    TerminalColors.accentGlow.opacity(0.14),
                    TerminalColors.accentGlow.opacity(0.04),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width * 0.42, height: size.height * 0.62)
            .blur(radius: 28)
            .offset(y: -size.height * 0.2)

            Rectangle()
                .fill(TerminalColors.border.opacity(0.55))
                .frame(width: size.width * 0.88, height: 1)
                .offset(y: size.height * 0.07)

        }
    }
}

// MARK: - Interaction layer (placed in .overlay for reliable hit testing)

struct GrassTapOverlay: View {
    let sessions: [SessionData]
    var selectedSessionId: String?
    @Binding var hoveredSessionId: String?
    var handoffSessionId: String?
    var handoffProgress: CGFloat = 1
    var isHandoffCollapsing = false
    var onSelectSession: ((String) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.clear

                if !sessions.isEmpty {
                    ForEach(SpriteLayout.depthSorted(sessions)) { session in
                        if shouldAllowInteraction(for: session.id) {
                            SpriteTapTarget(
                                sessionId: session.id,
                                xPosition: session.spriteXPosition,
                                yOffset: session.spriteYOffset,
                                totalWidth: geometry.size.width,
                                hoveredSessionId: $hoveredSessionId,
                                onTap: { onSelectSession?(session.id) }
                            )
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
    }

    private func shouldAllowInteraction(for sessionId: String) -> Bool {
        guard sessionId == handoffSessionId else { return true }
        return SpriteHandoffVisuals.isInteractive(
            for: handoffProgress,
            isCollapsing: isHandoffCollapsing
        )
    }
}

// MARK: - Private views

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct SpriteTapTarget: View {
    let sessionId: String
    let xPosition: CGFloat
    let yOffset: CGFloat
    let totalWidth: CGFloat
    @Binding var hoveredSessionId: String?
    var onTap: (() -> Void)?

    @State private var tapScale: CGFloat = 1.0

    var body: some View {
        Button(action: handleTap) {
            Color.clear
                .frame(width: SpriteLayout.size, height: SpriteLayout.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .onHover { hovering in
            hoveredSessionId = hovering ? sessionId : nil
        }
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
    var glowOpacity: Double = 0

    private let swayDuration: Double = 2.0
    private var bobAmplitude: CGFloat {
        guard state.bobAmplitude > 0 else { return 0 }
        return state.task == .working ? 1.5 : 1
    }
    private let glowColor = TerminalColors.accentGlow

    private var swayAmplitude: Double {
        (state.task == .sleeping || state.task == .compacting) ? 0 : state.swayAmplitude
    }

    private var isAnimatingMotion: Bool {
        bobAmplitude > 0 || swayAmplitude > 0
    }

    private var bobDuration: Double {
        state.task == .working ? 1.0 : state.bobDuration
    }

    private func swayDegrees(at date: Date) -> Double {
        guard swayAmplitude > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let phase = (t / swayDuration).truncatingRemainder(dividingBy: 1.0)
        return sin(phase * .pi * 2) * swayAmplitude
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimatingMotion)) { timeline in
            CodexAgentBadgeView(
                state: state,
                size: SpriteLayout.size,
                date: timeline.date,
                emphasis: glowOpacity * 0.35
            )
            .background(alignment: .bottom) {
                if glowOpacity > 0 {
                    Ellipse()
                        .fill(glowColor.opacity(glowOpacity))
                        .frame(width: SpriteLayout.size * 0.85, height: SpriteLayout.size * 0.25)
                        .blur(radius: 8)
                        .offset(y: 4)
                }
            }
            .rotationEffect(.degrees(swayDegrees(at: timeline.date)), anchor: .bottom)
            .offset(
                x: SpriteLayout.xOffset(xPosition: xPosition, totalWidth: totalWidth)
                    + trembleOffset(at: timeline.date, amplitude: 0),
                y: yOffset + bobOffset(at: timeline.date, duration: bobDuration, amplitude: bobAmplitude)
            )
        }
    }
}
