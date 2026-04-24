import SwiftUI

struct CodexAgentBadgeView: View {
    let state: NotchiState
    let size: CGFloat
    let date: Date
    var emphasis: Double = 0

    private var phase: Double {
        let t = date.timeIntervalSinceReferenceDate
        return (t / state.pulseDuration).truncatingRemainder(dividingBy: 1)
    }

    private var pulse: Double {
        0.5 + 0.5 * sin(phase * .pi * 2)
    }

    private var badgeScale: CGFloat {
        let pulseScale = state.shouldAnimatePulse ? CGFloat(0.985 + pulse * 0.025) : 1
        return state.avatarScale * pulseScale
    }

    private var glowOpacity: Double {
        switch state.task {
        case .working:
            return 0.38 + emphasis
        case .waiting:
            return 0.24 + emphasis
        case .compacting:
            return 0.3 + emphasis
        case .sleeping:
            return 0.12 + emphasis * 0.4
        case .idle:
            return 0.18 + emphasis * 0.5
        }
    }

    var body: some View {
        Image("CodexSystemLogo")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(badgeScale)
            .shadow(
                color: TerminalColors.accentGlow.opacity(glowOpacity * (0.7 + pulse * 0.3)),
                radius: size * 0.08
            )
            .drawingGroup()
    }
}
