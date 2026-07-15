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
    case back
    case thumbsUpBegan
    case thumbsUpEnded
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
    public var cannedGestureMinimumConfidence: Double
    public var victoryActivationSeconds: TimeInterval
    public var backMinimumDisplacement: Double
    public var backMovementWindowSeconds: TimeInterval
    public var backCooldownSeconds: TimeInterval
    public var gestureReleaseSeconds: TimeInterval
    public var thumbsUpActivationSeconds: TimeInterval

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
        minimumConfidence: Double = 0.55,
        cannedGestureMinimumConfidence: Double = 0.70,
        victoryActivationSeconds: TimeInterval = 0.22,
        backMinimumDisplacement: Double = 0.14,
        backMovementWindowSeconds: TimeInterval = 0.60,
        backCooldownSeconds: TimeInterval = 0.85,
        gestureReleaseSeconds: TimeInterval = 0.15,
        thumbsUpActivationSeconds: TimeInterval = 0.30
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
        self.cannedGestureMinimumConfidence = cannedGestureMinimumConfidence
        self.victoryActivationSeconds = victoryActivationSeconds
        self.backMinimumDisplacement = backMinimumDisplacement
        self.backMovementWindowSeconds = backMovementWindowSeconds
        self.backCooldownSeconds = backCooldownSeconds
        self.gestureReleaseSeconds = gestureReleaseSeconds
        self.thumbsUpActivationSeconds = thumbsUpActivationSeconds
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

    private var victoryCandidateSince: TimeInterval?
    private var backStartPalm: SwipeSample?
    private var backDeadline: TimeInterval = 0
    private var backNeedsRelease = false
    private var backReleaseObserved = false
    private var backCooldownUntil: TimeInterval = 0
    private var victoryExitSince: TimeInterval?

    private var thumbsUpCandidateSince: TimeInterval?
    private var thumbsUpActive = false
    private var thumbsUpAbsentSince: TimeInterval?

    public init(configuration: GestureConfiguration = .init()) {
        self.configuration = configuration
    }

    public func update(pose: HandPose?, at now: TimeInterval) -> [GestureOutput] {
        guard let pose, pose.confidence >= configuration.minimumConfidence else {
            return loseHand(at: now)
        }

        let pinchPoint = pinchCenter(pose)
        var output: [GestureOutput] = []

        if pinchActive {
            let remainsStrictOK = isStrictPinch(
                pose,
                pinchThreshold: configuration.pinchReleaseThreshold
            )
            if !remainsStrictOK || pinchPoint == nil {
                endPinch(into: &output)
            } else if let point = pinchPoint {
                let previous = lastPinchPoint ?? point
                lastPinchPoint = point
                let deltaY = point.y - previous.y
                let magnitude = abs(deltaY)
                if magnitude >= configuration.minimumPinchStep,
                   magnitude <= configuration.maximumPinchStep {
                    output.append(.pinchScroll(deltaY))
                }
                resetBackCompletely()
                output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
                resetSwipe(released: true, at: now)
                return output
            }
        }

        if !pinchActive,
           isStrictPinch(pose, pinchThreshold: configuration.pinchThreshold),
           let point = pinchPoint {
            pinchCandidateSince = pinchCandidateSince ?? now
            if now - (pinchCandidateSince ?? now) >= configuration.pinchActivationSeconds {
                pinchActive = true
                lastPinchPoint = point
                output.append(.pinchBegan)
            }
            resetBackCompletely()
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
            resetSwipe(released: true, at: now)
            return output
        }

        pinchCandidateSince = nil
        lastPinchPoint = nil

        let cannedGestureIsConfident =
            pose.gestureConfidence >= configuration.cannedGestureMinimumConfidence
        if cannedGestureIsConfident, pose.recognizedGesture == .victory {
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
            resetSwipe(released: true, at: now)
            output.append(contentsOf: updateBack(pose: pose, at: now))
            return output
        }

        observeVictoryRelease(at: now)

        if cannedGestureIsConfident, pose.recognizedGesture == .thumbUp {
            resetSwipe(released: true, at: now)
            output.append(contentsOf: updateThumbsUp(isDetected: true, at: now))
            return output
        }

        output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
        output.append(contentsOf: updateSwipe(pose: pose, at: now))
        return output
    }

    @discardableResult
    public func cancelActiveGesture() -> [GestureOutput] {
        var output: [GestureOutput] = []
        endPinch(into: &output)
        if thumbsUpActive { output.append(.thumbsUpEnded) }
        pinchCandidateSince = nil
        lastPinchPoint = nil
        thumbsUpCandidateSince = nil
        thumbsUpActive = false
        thumbsUpAbsentSince = nil
        resetBackCompletely()
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

    public func isThumbsUpRecognized() -> Bool {
        thumbsUpActive
    }

    private func loseHand(at now: TimeInterval) -> [GestureOutput] {
        var output: [GestureOutput] = []
        endPinch(into: &output)
        if thumbsUpActive { output.append(.thumbsUpEnded) }
        thumbsUpActive = false
        thumbsUpCandidateSince = nil
        thumbsUpAbsentSince = nil
        pinchCandidateSince = nil
        lastPinchPoint = nil
        resetBackCompletely()
        resetSwipe(released: true, at: now)
        return output
    }

    private func endPinch(into output: inout [GestureOutput]) {
        if pinchActive { output.append(.pinchEnded) }
        pinchActive = false
        pinchCandidateSince = nil
        lastPinchPoint = nil
    }

    private func updateBack(pose: HandPose, at now: TimeInterval) -> [GestureOutput] {
        if backNeedsRelease {
            guard backReleaseObserved, now >= backCooldownUntil else { return [] }
            backNeedsRelease = false
            backReleaseObserved = false
            backCooldownUntil = 0
        }
        victoryExitSince = nil
        guard let palm = palmCenter(pose) else { return [] }

        let mirrored = SwipeSample(x: 1 - palm.x, y: palm.y, time: now)
        victoryCandidateSince = victoryCandidateSince ?? now
        guard now - (victoryCandidateSince ?? now) >= configuration.victoryActivationSeconds else {
            return []
        }

        if backStartPalm == nil {
            backStartPalm = mirrored
            backDeadline = now + configuration.backMovementWindowSeconds
            return []
        }

        if now > backDeadline {
            victoryCandidateSince = now
            backStartPalm = nil
            return []
        }

        guard let start = backStartPalm else { return [] }
        let deltaX = mirrored.x - start.x
        let deltaY = mirrored.y - start.y
        guard deltaX <= -configuration.backMinimumDisplacement,
              abs(deltaX) >= abs(deltaY) * 1.4 else { return [] }

        backNeedsRelease = true
        backReleaseObserved = false
        backCooldownUntil = now + configuration.backCooldownSeconds
        victoryCandidateSince = nil
        backStartPalm = nil
        backDeadline = 0
        return [.back]
    }

    private func observeVictoryRelease(at now: TimeInterval) {
        victoryCandidateSince = nil
        backStartPalm = nil
        backDeadline = 0
        guard backNeedsRelease else { return }
        victoryExitSince = victoryExitSince ?? now
        if now - (victoryExitSince ?? now) >= configuration.gestureReleaseSeconds {
            backReleaseObserved = true
        }
        if backReleaseObserved, now >= backCooldownUntil {
            backNeedsRelease = false
            backReleaseObserved = false
            backCooldownUntil = 0
            victoryExitSince = nil
        }
    }

    private func resetBackCompletely() {
        victoryCandidateSince = nil
        backStartPalm = nil
        backDeadline = 0
        backNeedsRelease = false
        backReleaseObserved = false
        backCooldownUntil = 0
        victoryExitSince = nil
    }

    private func updateThumbsUp(isDetected: Bool, at now: TimeInterval) -> [GestureOutput] {
        if isDetected {
            thumbsUpAbsentSince = nil
            thumbsUpCandidateSince = thumbsUpCandidateSince ?? now
            if !thumbsUpActive,
               now - (thumbsUpCandidateSince ?? now) >= configuration.thumbsUpActivationSeconds {
                thumbsUpActive = true
                return [.thumbsUpBegan]
            }
            return []
        }

        thumbsUpCandidateSince = nil
        guard thumbsUpActive else {
            thumbsUpAbsentSince = nil
            return []
        }
        thumbsUpAbsentSince = thumbsUpAbsentSince ?? now
        guard now - (thumbsUpAbsentSince ?? now) >= configuration.gestureReleaseSeconds else {
            return []
        }
        thumbsUpActive = false
        thumbsUpAbsentSince = nil
        return [.thumbsUpEnded]
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
