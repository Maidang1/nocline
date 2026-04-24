import CoreGraphics

enum NotchiTask: String, CaseIterable {
    case idle, working, sleeping, compacting, waiting

    var animationFPS: Double {
        switch self {
        case .compacting: return 6.0
        case .sleeping: return 2.0
        case .idle, .waiting: return 3.0
        case .working: return 4.0
        }
    }

    var bobDuration: Double {
        switch self {
        case .sleeping:   return 4.0
        case .idle, .waiting: return 1.5
        case .working:    return 0.4
        case .compacting: return 0.5
        }
    }

    var bobAmplitude: CGFloat {
        switch self {
        case .sleeping, .compacting: return 0
        case .idle:                  return 1.5
        case .waiting:               return 0.5
        case .working:               return 0.5
        }
    }

    var canWalk: Bool {
        switch self {
        case .sleeping, .compacting, .waiting:
            return false
        case .idle, .working:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .idle:       return "Idle"
        case .working:    return "Working..."
        case .sleeping:   return "Sleeping"
        case .compacting: return "Compacting..."
        case .waiting:    return "Waiting..."
        }
    }

    var walkFrequencyRange: ClosedRange<Double> {
        switch self {
        case .sleeping, .waiting: return 30.0...60.0
        case .idle:               return 8.0...15.0
        case .working:            return 5.0...12.0
        case .compacting:         return 15.0...25.0
        }
    }

    var avatarScale: CGFloat {
        switch self {
        case .sleeping: return 0.92
        case .compacting: return 0.94
        case .idle, .waiting, .working: return 1.0
        }
    }

    var pulseDuration: Double {
        switch self {
        case .sleeping: return 3.6
        case .idle: return 2.6
        case .waiting: return 1.8
        case .working: return 1.1
        case .compacting: return 1.4
        }
    }
}

struct NotchiState: Equatable {
    var task: NotchiTask

    var animationFPS: Double { task.animationFPS }
    var bobDuration: Double { task.bobDuration }
    var bobAmplitude: CGFloat { task.bobAmplitude }
    var swayAmplitude: Double { 0.5 }
    var canWalk: Bool { task.canWalk }
    var displayName: String { task.displayName }
    var walkFrequencyRange: ClosedRange<Double> { task.walkFrequencyRange }
    var avatarScale: CGFloat { task.avatarScale }
    var pulseDuration: Double { task.pulseDuration }
    var haloOpacity: Double {
        switch task {
        case .sleeping: return 0.08
        case .idle: return 0.18
        case .waiting: return 0.22
        case .working: return 0.34
        case .compacting: return 0.26
        }
    }
    var activityArcOpacity: Double {
        switch task {
        case .working: return 1
        case .waiting: return 0.55
        case .compacting: return 0.8
        case .idle, .sleeping: return 0
        }
    }
    var shellOpacity: Double {
        switch task {
        case .sleeping: return 0.72
        case .idle: return 0.88
        case .waiting, .compacting, .working: return 1
        }
    }
    var shouldAnimatePulse: Bool { true }

    static let idle = NotchiState(task: .idle)
    static let working = NotchiState(task: .working)
    static let sleeping = NotchiState(task: .sleeping)
    static let compacting = NotchiState(task: .compacting)
    static let waiting = NotchiState(task: .waiting)
}
