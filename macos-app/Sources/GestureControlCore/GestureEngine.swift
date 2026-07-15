import Foundation

public enum PageDirection: Equatable, Sendable {
    case up
    case down
}

public enum GestureOutput: Equatable, Sendable {
    case pinchBegan
    case pinchScroll(Double)
    case pinchEnded
    case page(PageDirection)
}

public struct GestureConfiguration: Equatable, Sendable {
    public var pinchThreshold: Double
    public var pinchReleaseThreshold: Double
    public var pinchActivationSeconds: TimeInterval
    public var minimumPinchStep: Double
    public var maximumPinchStep: Double
    public var swipeMinimumDisplacement: Double
    public var swipeHistorySeconds: TimeInterval
    public var swipeMinimumDuration: TimeInterval
    public var swipeCooldownSeconds: TimeInterval
    public var minimumConfidence: Double

    public init(
        pinchThreshold: Double = 0.18,
        pinchReleaseThreshold: Double = 0.20,
        pinchActivationSeconds: TimeInterval = 0.08,
        minimumPinchStep: Double = 0.003,
        maximumPinchStep: Double = 0.12,
        swipeMinimumDisplacement: Double = 0.16,
        swipeHistorySeconds: TimeInterval = 0.36,
        swipeMinimumDuration: TimeInterval = 0.10,
        swipeCooldownSeconds: TimeInterval = 0.65,
        minimumConfidence: Double = 0.55
    ) {
        self.pinchThreshold = pinchThreshold
        self.pinchReleaseThreshold = pinchReleaseThreshold
        self.pinchActivationSeconds = pinchActivationSeconds
        self.minimumPinchStep = minimumPinchStep
        self.maximumPinchStep = maximumPinchStep
        self.swipeMinimumDisplacement = swipeMinimumDisplacement
        self.swipeHistorySeconds = swipeHistorySeconds
        self.swipeMinimumDuration = swipeMinimumDuration
        self.swipeCooldownSeconds = swipeCooldownSeconds
        self.minimumConfidence = minimumConfidence
    }
}

public final class GestureEngine {
    public var configuration: GestureConfiguration

    private struct SwipeSample {
        var x: Double
        var y: Double
        var time: TimeInterval
    }

    private var pinchCandidateSince: TimeInterval?
    private var pinchActive = false
    private var lastPinchPoint: NormalizedPoint?
    private var swipeSamples: [SwipeSample] = []
    private var swipeArmed = true
    private var swipeCooldownUntil: TimeInterval = 0
    private var swipeReleaseObserved = false
    private var swipeStableSince: TimeInterval?
    private var lastRearmPalm: SwipeSample?

    public init(configuration: GestureConfiguration = .init()) {
        self.configuration = configuration
    }

    public func update(pose: HandPose?, at now: TimeInterval) -> [GestureOutput] {
        guard let pose, pose.confidence >= configuration.minimumConfidence else {
            return loseHand(at: now)
        }

        let strength = pinchStrength(pose)
        let pinchPoint = pinchCenter(pose)
        var output: [GestureOutput] = []

        if pinchActive {
            if strength >= configuration.pinchReleaseThreshold || pinchPoint == nil {
                endPinch(into: &output)
            } else if let point = pinchPoint {
                let previous = lastPinchPoint ?? point
                lastPinchPoint = point
                let deltaY = point.y - previous.y
                let magnitude = abs(deltaY)
                if magnitude >= configuration.minimumPinchStep && magnitude <= configuration.maximumPinchStep {
                    output.append(.pinchScroll(deltaY))
                }
                resetSwipe(released: true, at: now)
                return output
            }
        }

        if !pinchActive, strength <= configuration.pinchThreshold, let point = pinchPoint {
            pinchCandidateSince = pinchCandidateSince ?? now
            if now - (pinchCandidateSince ?? now) >= configuration.pinchActivationSeconds {
                pinchActive = true
                lastPinchPoint = point
                output.append(.pinchBegan)
            }
            resetSwipe(released: true, at: now)
            return output
        }

        pinchCandidateSince = nil
        lastPinchPoint = nil
        output.append(contentsOf: updateSwipe(pose: pose, at: now))
        return output
    }

    @discardableResult
    public func cancelActiveGesture() -> [GestureOutput] {
        var output: [GestureOutput] = []
        endPinch(into: &output)
        pinchCandidateSince = nil
        lastPinchPoint = nil
        swipeSamples = []
        swipeArmed = true
        swipeCooldownUntil = 0
        swipeReleaseObserved = false
        swipeStableSince = nil
        lastRearmPalm = nil
        return output
    }

    public func isPinching() -> Bool {
        pinchActive
    }

    private func loseHand(at now: TimeInterval) -> [GestureOutput] {
        var output: [GestureOutput] = []
        endPinch(into: &output)
        pinchCandidateSince = nil
        lastPinchPoint = nil
        resetSwipe(released: true, at: now)
        return output
    }

    private func endPinch(into output: inout [GestureOutput]) {
        if pinchActive { output.append(.pinchEnded) }
        pinchActive = false
        pinchCandidateSince = nil
        lastPinchPoint = nil
    }

    private func updateSwipe(pose: HandPose, at now: TimeInterval) -> [GestureOutput] {
        guard isOpenPalm(pose), let palm = palmCenter(pose) else {
            resetSwipe(released: true, at: now)
            return []
        }

        if !swipeArmed {
            if swipeReleaseObserved && now >= swipeCooldownUntil {
                rearm(with: palm, at: now)
            } else {
                let mirrored = SwipeSample(x: 1 - palm.x, y: palm.y, time: now)
                let movement = lastRearmPalm.map { hypot(mirrored.x - $0.x, mirrored.y - $0.y) } ?? 0
                if lastRearmPalm == nil || movement > 0.018 {
                    swipeStableSince = now
                } else if swipeStableSince == nil {
                    swipeStableSince = now
                }
                lastRearmPalm = mirrored
                if let stableSince = swipeStableSince,
                   now - stableSince >= 0.18,
                   now >= swipeCooldownUntil {
                    rearm(with: palm, at: now)
                } else {
                    return []
                }
            }
        }

        // Mirror the camera coordinate so physical left/right matches the user.
        swipeSamples.append(SwipeSample(x: 1 - palm.x, y: palm.y, time: now))
        swipeSamples.removeAll { now - $0.time > configuration.swipeHistorySeconds }
        guard let first = swipeSamples.first else { return [] }
        let duration = now - first.time
        guard duration >= configuration.swipeMinimumDuration else { return [] }

        let current = swipeSamples[swipeSamples.count - 1]
        let deltaX = current.x - first.x
        let deltaY = current.y - first.y
        guard abs(deltaX) >= configuration.swipeMinimumDisplacement,
              abs(deltaX) >= abs(deltaY) * 1.4 else { return [] }

        swipeArmed = false
        swipeReleaseObserved = false
        swipeCooldownUntil = now + configuration.swipeCooldownSeconds
        swipeSamples = []
        swipeStableSince = nil
        lastRearmPalm = SwipeSample(x: current.x, y: current.y, time: now)
        return [.page(deltaX < 0 ? .up : .down)]
    }

    private func resetSwipe(released: Bool, at now: TimeInterval) {
        swipeSamples = []
        if !swipeArmed && released {
            swipeReleaseObserved = true
            if now >= swipeCooldownUntil {
                swipeArmed = true
                swipeReleaseObserved = false
                swipeStableSince = nil
                lastRearmPalm = nil
            }
        }
    }

    private func rearm(with palm: NormalizedPoint, at now: TimeInterval) {
        swipeArmed = true
        swipeReleaseObserved = false
        swipeCooldownUntil = 0
        swipeStableSince = nil
        lastRearmPalm = nil
        swipeSamples = [SwipeSample(x: 1 - palm.x, y: palm.y, time: now)]
    }
}
