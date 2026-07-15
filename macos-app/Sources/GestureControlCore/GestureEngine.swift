import Foundation

public enum PageDirection: Equatable, Sendable {
    case up
    case down
}

public enum NavigationDirection: Equatable, Sendable {
    case back
    case forward
}

public enum PinchInteractionMode: Equatable, Sendable {
    case inactive
    case undecided
    case scrolling
    case navigation(NavigationDirection?)
}

public enum GestureOutput: Equatable, Sendable {
    case pinchBegan
    case pinchScroll(Double)
    case pinchEnded
    case page(PageDirection)
    case navigate(NavigationDirection)
    case thumbsUpBegan
    case thumbsUpEnded
}

public struct GestureConfiguration: Equatable, Sendable {
    public var pinchThreshold: Double
    public var pinchReleaseThreshold: Double
    public var pinchActivationSeconds: TimeInterval
    public var minimumPinchStep: Double
    public var maximumPinchStep: Double
    public var pinchVerticalIntentThreshold: Double
    public var pinchHorizontalIntentThreshold: Double
    public var pinchVerticalDominance: Double
    public var horizontalDominance: Double
    public var navigationCenterGuard: Double
    public var navigationCenterX: Double
    public var swipeMinimumDisplacement: Double
    public var minimumConfidence: Double
    public var cannedGestureMinimumConfidence: Double
    public var pointingActivationSeconds: TimeInterval
    public var pointingClassificationGraceSeconds: TimeInterval
    public var gestureReleaseSeconds: TimeInterval
    public var thumbsUpActivationSeconds: TimeInterval

    public init(
        pinchThreshold: Double = 0.18,
        pinchReleaseThreshold: Double = 0.20,
        pinchActivationSeconds: TimeInterval = 0.08,
        minimumPinchStep: Double = 0.003,
        maximumPinchStep: Double = 0.12,
        pinchVerticalIntentThreshold: Double = 0.025,
        pinchHorizontalIntentThreshold: Double = 0.04,
        pinchVerticalDominance: Double = 1.35,
        horizontalDominance: Double = 1.40,
        navigationCenterGuard: Double = 0.07,
        navigationCenterX: Double = 0.50,
        swipeMinimumDisplacement: Double = 0.14,
        minimumConfidence: Double = 0.55,
        cannedGestureMinimumConfidence: Double = 0.70,
        pointingActivationSeconds: TimeInterval = 0.22,
        pointingClassificationGraceSeconds: TimeInterval = 0.18,
        gestureReleaseSeconds: TimeInterval = 0.15,
        thumbsUpActivationSeconds: TimeInterval = 0.30
    ) {
        self.pinchThreshold = pinchThreshold
        self.pinchReleaseThreshold = pinchReleaseThreshold
        self.pinchActivationSeconds = pinchActivationSeconds
        self.minimumPinchStep = minimumPinchStep
        self.maximumPinchStep = maximumPinchStep
        self.pinchVerticalIntentThreshold = pinchVerticalIntentThreshold
        self.pinchHorizontalIntentThreshold = pinchHorizontalIntentThreshold
        self.pinchVerticalDominance = pinchVerticalDominance
        self.horizontalDominance = horizontalDominance
        self.navigationCenterGuard = navigationCenterGuard
        self.navigationCenterX = navigationCenterX
        self.swipeMinimumDisplacement = swipeMinimumDisplacement
        self.minimumConfidence = minimumConfidence
        self.cannedGestureMinimumConfidence = cannedGestureMinimumConfidence
        self.pointingActivationSeconds = pointingActivationSeconds
        self.pointingClassificationGraceSeconds = pointingClassificationGraceSeconds
        self.gestureReleaseSeconds = gestureReleaseSeconds
        self.thumbsUpActivationSeconds = thumbsUpActivationSeconds
    }
}

public final class GestureEngine {
    public var configuration: GestureConfiguration

    private var pinchCandidateSince: TimeInterval?
    private var pinchActive = false
    private var pinchMode: PinchInteractionMode = .inactive
    private var pinchStartPoint: NormalizedPoint?
    private var lastPinchPoint: NormalizedPoint?
    private var pinchNavigationTriggered = false

    private var pointingCandidateSince: TimeInterval?
    private var pointingStartTip: NormalizedPoint?
    private var pointingActive = false
    private var pointingLastConfirmedAt: TimeInterval?
    private var pointingNeedsRelease = false
    private var pointingExitSince: TimeInterval?

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

        let pinchPoint = pinchCenter(pose).map(screenPoint)
        var output: [GestureOutput] = []

        if pinchActive {
            let remainsStrictOK = isStrictPinch(
                pose,
                pinchThreshold: configuration.pinchReleaseThreshold
            )
            if !remainsStrictOK || pinchPoint == nil {
                endPinch(into: &output)
            } else if let point = pinchPoint {
                output.append(contentsOf: updateActivePinch(point: point))
                observePointingRelease(at: now)
                output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
                return output
            }
        }

        if !pinchActive,
           isStrictPinch(pose, pinchThreshold: configuration.pinchThreshold),
           let point = pinchPoint {
            pinchCandidateSince = pinchCandidateSince ?? now
            if now - (pinchCandidateSince ?? now) >= configuration.pinchActivationSeconds {
                pinchActive = true
                pinchMode = .undecided
                pinchStartPoint = point
                lastPinchPoint = point
                pinchNavigationTriggered = false
                output.append(.pinchBegan)
            }
            observePointingRelease(at: now)
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
            return output
        }

        pinchCandidateSince = nil
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false

        let cannedGestureIsConfident =
            pose.gestureConfidence >= configuration.cannedGestureMinimumConfidence
        if cannedGestureIsConfident,
           pose.recognizedGesture == .pointingUp,
           isStrictPointing(pose) {
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
            output.append(contentsOf: updatePointingPage(pose: pose, at: now, confirmed: true))
            return output
        }

        if pointingActive,
           let lastConfirmedAt = pointingLastConfirmedAt,
           now - lastConfirmedAt <= configuration.pointingClassificationGraceSeconds,
           isStrictPointing(pose) {
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
            output.append(contentsOf: updatePointingPage(pose: pose, at: now, confirmed: false))
            return output
        }

        observePointingRelease(at: now)

        if cannedGestureIsConfident, pose.recognizedGesture == .thumbUp {
            output.append(contentsOf: updateThumbsUp(isDetected: true, at: now))
            return output
        }

        output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
        return output
    }

    @discardableResult
    public func cancelActiveGesture() -> [GestureOutput] {
        var output: [GestureOutput] = []
        endPinch(into: &output)
        if thumbsUpActive { output.append(.thumbsUpEnded) }
        pinchCandidateSince = nil
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false
        thumbsUpCandidateSince = nil
        thumbsUpActive = false
        thumbsUpAbsentSince = nil
        resetPointingCompletely()
        return output
    }

    public func isPinching() -> Bool {
        pinchActive
    }

    public func pinchInteractionMode() -> PinchInteractionMode {
        pinchMode
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
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false
        observePointingRelease(at: now)
        return output
    }

    private func endPinch(into output: inout [GestureOutput]) {
        if pinchActive { output.append(.pinchEnded) }
        pinchActive = false
        pinchCandidateSince = nil
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false
    }

    private func updateActivePinch(point: NormalizedPoint) -> [GestureOutput] {
        guard let start = pinchStartPoint else {
            pinchStartPoint = point
            lastPinchPoint = point
            return []
        }

        let totalDeltaX = point.x - start.x
        let totalDeltaY = point.y - start.y
        if pinchMode == .undecided {
            if abs(totalDeltaY) >= configuration.pinchVerticalIntentThreshold,
               abs(totalDeltaY) >= abs(totalDeltaX) * configuration.pinchVerticalDominance {
                pinchMode = .scrolling
            } else if abs(totalDeltaX) >= configuration.pinchHorizontalIntentThreshold,
                      abs(totalDeltaX) >= abs(totalDeltaY) * configuration.horizontalDominance {
                pinchMode = .navigation(navigationDirection(forStartX: start.x))
            }
        }

        switch pinchMode {
        case .inactive, .undecided:
            lastPinchPoint = point
            return []
        case .scrolling:
            let previous = lastPinchPoint ?? start
            lastPinchPoint = point
            let deltaY = point.y - previous.y
            let magnitude = abs(deltaY)
            guard magnitude >= configuration.minimumPinchStep,
                  magnitude <= configuration.maximumPinchStep else { return [] }
            return [.pinchScroll(deltaY)]
        case let .navigation(direction):
            lastPinchPoint = point
            guard let direction,
                  !pinchNavigationTriggered,
                  crossedCenter(from: start, to: point, direction: direction) else { return [] }
            pinchNavigationTriggered = true
            return [.navigate(direction)]
        }
    }

    private func updatePointingPage(
        pose: HandPose,
        at now: TimeInterval,
        confirmed: Bool
    ) -> [GestureOutput] {
        guard let current = pose.point(.indexTip).map(screenPoint) else { return [] }
        if confirmed {
            pointingLastConfirmedAt = now
            pointingExitSince = nil
        }
        guard !pointingNeedsRelease else { return [] }

        if pointingCandidateSince == nil {
            pointingCandidateSince = now
            pointingStartTip = current
            pointingActive = false
            return []
        }

        if !pointingActive {
            guard now - (pointingCandidateSince ?? now) >= configuration.pointingActivationSeconds else {
                return []
            }
            pointingActive = true
        }

        guard let start = pointingStartTip,
              let direction = navigationDirection(forStartX: start.x),
              crossedCenter(from: start, to: current, direction: direction) else { return [] }

        pointingNeedsRelease = true
        pointingCandidateSince = nil
        pointingStartTip = nil
        pointingActive = false
        pointingLastConfirmedAt = nil
        return [.page(direction == .back ? .down : .up)]
    }

    private func observePointingRelease(at now: TimeInterval) {
        pointingCandidateSince = nil
        pointingStartTip = nil
        pointingActive = false
        pointingLastConfirmedAt = nil
        guard pointingNeedsRelease else { return }
        pointingExitSince = pointingExitSince ?? now
        if now - (pointingExitSince ?? now) >= configuration.gestureReleaseSeconds {
            pointingNeedsRelease = false
            pointingExitSince = nil
        }
    }

    private func resetPointingCompletely() {
        pointingCandidateSince = nil
        pointingStartTip = nil
        pointingActive = false
        pointingLastConfirmedAt = nil
        pointingNeedsRelease = false
        pointingExitSince = nil
    }

    private func navigationDirection(forStartX x: Double) -> NavigationDirection? {
        let center = configuration.navigationCenterX
        if x <= center - configuration.navigationCenterGuard { return .back }
        if x >= center + configuration.navigationCenterGuard { return .forward }
        return nil
    }

    private func crossedCenter(
        from start: NormalizedPoint,
        to current: NormalizedPoint,
        direction: NavigationDirection
    ) -> Bool {
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y
        let minimumDisplacement = max(0.14, configuration.swipeMinimumDisplacement)
        guard abs(deltaX) >= minimumDisplacement,
              abs(deltaX) >= abs(deltaY) * configuration.horizontalDominance else { return false }
        switch direction {
        case .back:
            return deltaX > 0 && current.x >= configuration.navigationCenterX
        case .forward:
            return deltaX < 0 && current.x <= configuration.navigationCenterX
        }
    }

    private func screenPoint(_ point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: 1 - point.x, y: point.y, confidence: point.confidence)
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

}
