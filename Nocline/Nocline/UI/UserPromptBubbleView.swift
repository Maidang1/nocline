import SwiftUI

struct UserPromptBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(TerminalColors.promptBubbleText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [TerminalColors.promptBubbleStart, TerminalColors.promptBubbleEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(TerminalColors.accent.opacity(0.45), lineWidth: 1)
                    )
            )
    }
}
