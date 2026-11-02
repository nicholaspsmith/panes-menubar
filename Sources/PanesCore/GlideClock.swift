import Foundation

/// The clock of one glide. It starts when the first step has reached the
/// window (an app can take several frames to apply it, and a clock that ran
/// meanwhile would make the glide skip ahead), or one frame after creation,
/// whichever comes first.
public struct GlideClock {
    private let created: TimeInterval
    private let frameInterval: TimeInterval
    private var started: TimeInterval?
    /// Seconds from the start to the latest tick; nil until the clock has started.
    public private(set) var elapsed: TimeInterval?

    public init(created: TimeInterval, frameInterval: TimeInterval) {
        self.created = created
        self.frameInterval = frameInterval
    }

    /// Call each tick with whether the window's frame now reads back the first step.
    public mutating func tick(now: TimeInterval, firstStepLanded: Bool) {
        if started == nil, firstStepLanded || now - created >= frameInterval { started = now }
        if let started { elapsed = now - started }
    }
}
