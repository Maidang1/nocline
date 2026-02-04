//
//  AssistantTextRowView.swift
//  notchi
//
//  Displays assistant text messages as bullet-pointed items in the activity panel.
//

import SwiftUI

struct AssistantTextRowView: View {
    let message: AssistantMessage

    private static let maxDisplayLength = 120

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(TerminalColors.claudeOrange.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(truncatedText)
                .font(.system(size: 12).italic())
                .foregroundColor(TerminalColors.primaryText.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var truncatedText: String {
        let cleaned = message.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > Self.maxDisplayLength else { return cleaned }
        let index = cleaned.index(cleaned.startIndex, offsetBy: Self.maxDisplayLength)
        return String(cleaned[..<index]) + "..."
    }
}
