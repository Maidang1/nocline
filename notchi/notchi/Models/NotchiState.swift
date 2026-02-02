enum NotchiState: String, CaseIterable {
    case idle, thinking, working, happy, alert, sleeping

    var sfSymbolName: String {
        switch self {
        case .idle:     return "face.smiling"
        case .thinking: return "ellipsis.circle"
        case .working:  return "hammer"
        case .happy:    return "face.smiling.fill"
        case .alert:    return "exclamationmark.triangle"
        case .sleeping: return "moon.zzz"
        }
    }

    var bobDuration: Double {
        switch self {
        case .sleeping: return 4.0
        case .idle:     return 1.5
        case .thinking: return 0.8
        case .working:  return 0.4
        case .happy:    return 0.6
        case .alert:    return 0.3
        }
    }

    var displayName: String {
        switch self {
        case .idle:     return "Idle"
        case .thinking: return "Thinking..."
        case .working:  return "Working..."
        case .happy:    return "Done!"
        case .alert:    return "Error"
        case .sleeping: return "Sleeping"
        }
    }

    var canWalk: Bool {
        switch self {
        case .sleeping, .alert:
            return false
        default:
            return true
        }
    }

    var swayAmplitude: Double {
        switch self {
        case .sleeping: return 1.0
        case .idle:     return 3.0
        case .thinking: return 5.0
        case .working:  return 4.0
        case .happy:    return 8.0
        case .alert:    return 2.0
        }
    }

    var walkFrequencyRange: ClosedRange<Double> {
        switch self {
        case .sleeping: return 30.0...60.0
        case .idle:     return 8.0...15.0
        case .thinking: return 3.0...8.0
        case .working:  return 5.0...12.0
        case .happy:    return 2.0...5.0
        case .alert:    return 20.0...30.0
        }
    }
}
