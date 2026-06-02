import Foundation

public enum SessionStatus: Equatable, Sendable {
    case starting
    case working
    case idle
    case exited
}
