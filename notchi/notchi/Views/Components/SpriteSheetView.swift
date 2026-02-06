import SwiftUI

struct SpriteSheetView: View {
    let spriteSheet: String
    var frameCount: Int = 6
    var fps: Double = 10
    var isAnimating: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: !isAnimating)) { timeline in
            SpriteFrameView(
                spriteSheet: spriteSheet,
                frameCount: frameCount,
                currentFrame: currentFrame(at: timeline.date)
            )
        }
    }

    private func currentFrame(at date: Date) -> Int {
        guard isAnimating else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
        return Int(elapsed * fps) % frameCount
    }
}

private struct SpriteFrameView: View {
    let spriteSheet: String
    let frameCount: Int
    let currentFrame: Int

    var body: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width
            let sheetWidth = frameWidth * CGFloat(frameCount)

            Image(spriteSheet)
                .interpolation(.none)
                .resizable()
                .frame(width: sheetWidth, height: geometry.size.height)
                .offset(x: -frameWidth * CGFloat(currentFrame))
        }
        .clipped()
    }
}
