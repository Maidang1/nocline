//
//  AssistantTextRowView.swift
//  notchi
//
//  Displays assistant text messages as bullet-pointed items in the activity panel.
//

import SwiftUI

struct AssistantTextRowView: View {
    let message: AssistantMessage

    @State private var isExpanded = false
    private static let maxDisplayLength = 120

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(TerminalColors.iMessageBlue)

            Text(isExpanded ? cleanedText : truncatedText)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(isExpanded ? nil : 2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TerminalColors.secondaryText)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var cleanedText: String {
        message.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private var truncatedText: String {
        guard cleanedText.count > Self.maxDisplayLength else { return cleanedText }
        let index = cleanedText.index(cleanedText.startIndex, offsetBy: Self.maxDisplayLength)
        return String(cleanedText[..<index]) + "..."
    }
}
