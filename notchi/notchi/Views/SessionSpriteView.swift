import SwiftUI

struct SessionSpriteView: View {
    let state: NotchiState
    let isSelected: Bool

    private var bobAmplitude: CGFloat {
        guard state.bobAmplitude > 0 else { return 0 }
        return isSelected ? state.bobAmplitude : state.bobAmplitude * 0.67
    }

    private func bobOffset(at date: Date) -> CGFloat {
        guard bobAmplitude > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let phase = (t / state.bobDuration).truncatingRemainder(dividingBy: 1.0)
        // Ease-in-out sine wave: smooth up and down
        let wave = sin(phase * .pi * 2)
        return wave * bobAmplitude
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: bobAmplitude == 0)) { timeline in
            SpriteSheetView(
                spriteSheet: state.spriteSheetName,
                frameCount: state.frameCount,
                columns: state.columns,
                fps: state.animationFPS,
                isAnimating: true
            )
            .frame(width: 30, height: 30)
            .offset(y: bobOffset(at: timeline.date))
        }
    }
}
