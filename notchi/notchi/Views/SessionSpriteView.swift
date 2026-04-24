import SwiftUI

struct SessionSpriteView: View {
    let state: NotchiState
    let isSelected: Bool

    private var bobAmplitude: CGFloat {
        guard state.bobAmplitude > 0 else { return 0 }
        return isSelected ? state.bobAmplitude : state.bobAmplitude * 0.67
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !state.shouldAnimatePulse && bobAmplitude == 0)) { timeline in
            CodexAgentBadgeView(
                state: state,
                size: 30,
                date: timeline.date,
                emphasis: isSelected ? 0.12 : 0
            )
            .offset(
                x: trembleOffset(at: timeline.date, amplitude: 0),
                y: bobOffset(at: timeline.date, duration: state.bobDuration, amplitude: bobAmplitude)
            )
        }
    }
}
