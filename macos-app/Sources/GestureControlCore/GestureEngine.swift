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

public enum PointerInteractionState: Equatable, Sendable {
    case moving
    case clickReady
    case clickArmed
}

public enum GestureOutput: Equatable, Sendable {
    case pinchBegan
    case pinchScroll(Double)
    case pinchEnded
    case page(PageDirection)
    case navigate(NavigationDirection)
    case pointerMoved(NormalizedPoint, PointerInteractionState)
    case pointerClicked(NormalizedPoint)
    case pointerClickRejected
    case pointerEnded
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
    public var swipeHistorySeconds: TimeInterval
    public var swipeMinimumDuration: TimeInterval
    public var swipeCooldownSeconds: TimeInterval
    public var minimumConfidence: Double
    public var cannedGestureMinimumConfidence: Double
    public var pointerActivationSeconds: TimeInterval
    public var pointerClassificationGraceSeconds: TimeInterval
    public var pointerStableSeconds: TimeInterval
    public var pointerStableRadius: Double
    public var pointerMaximumJump: Double
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
        swipeHistorySeconds: TimeInterval = 0.36,
        swipeMinimumDuration: TimeInterval = 0.10,
        swipeCooldownSeconds: TimeInterval = 0.65,
        minimumConfidence: Double = 0.55,
        cannedGestureMinimumConfidence: Double = 0.70,
        pointerActivationSeconds: TimeInterval = 0.15,
        pointerClassificationGraceSeconds: TimeInterval = 0.18,
        pointerStableSeconds: TimeInterval = 0.35,
        pointerStableRadius: Double = 0.012,
        pointerMaximumJump: Double = 0.18,
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
        self.swipeHistorySeconds = swipeHistorySeconds
        self.swipeMinimumDuration = swipeMinimumDuration
        self.swipeCooldownSeconds = swipeCooldownSeconds
        self.minimumConfidence = minimumConfidence
        self.cannedGestureMinimumConfidence = cannedGestureMinimumConfidence
        self.pointerActivationSeconds = pointerActivationSeconds
        self.pointerClassificationGraceSeconds = pointerClassificationGraceSeconds
        self.pointerStableSeconds = pointerStableSeconds
        self.pointerStableRadius = pointerStableRadius
        self.pointerMaximumJump = pointerMaximumJump
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
    private var pinchMode: PinchInteractionMode = .inactive
    private var pinchStartPoint: NormalizedPoint?
    private var lastPinchPoint: NormalizedPoint?
    private var pinchNavigationTriggered = false

    private var swipeSamples: [SwipeSample] = []
    private var swipeArmed = true
    private var swipeCooldownUntil: TimeInterval = 0
    private var swipeReleaseObserved = false
    private var swipeStableSince: TimeInterval?
    private var lastRearmPalm: SwipeSample?

    private var pointerCandidateSince: TimeInterval?
    private var pointerActive = false
    private var pointerLastConfirmedAt: TimeInterval?
    private var pointerLastPoint: NormalizedPoint?
    private var pointerStableAnchor: NormalizedPoint?
    private var pointerStableSince: TimeInterval?
    private var pointerClickReady = false
    private var pointerClickContactCandidateSince: TimeInterval?
    private var pointerClickContactConsumed = false

    private var thumbsUpCandidateSince: TimeInterval?
    private var thumbsUpActive = false
    private var thumbsUpAbsentSince: TimeInterval?

    public init(configuration: GestureConfiguration = .init()) {
        self.configuration = configuration
    }

    public func update(
        pose: HandPose?,
        at now: TimeInterval,
        pointerModeEnabled: Bool = false
    ) -> [GestureOutput] {
        guard let pose, pose.confidence >= configuration.minimumConfidence else {
            return loseHand(at: now)
        }

        let pinchPoint = pinchCenter(pose).map(screenPoint)
        var output: [GestureOutput] = []
        if !pointerModeEnabled {
            endPointer(into: &output)
            resetPointerCompletely()
        }

        if pinchActive {
            let remainsStrictOK = isStrictPinch(
                pose,
                pinchThreshold: configuration.pinchReleaseThreshold
            )
            if !remainsStrictOK || pinchPoint == nil {
                endPinch(into: &output)
            } else if let point = pinchPoint {
                endPointer(into: &output)
                resetPointerCompletely()
                output.append(contentsOf: updateActivePinch(point: point))
                resetSwipe(released: true, at: now)
                output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
                return output
            }
        }

        if !pinchActive,
           isStrictPinch(pose, pinchThreshold: configuration.pinchThreshold),
           let point = pinchPoint {
            endPointer(into: &output)
            resetPointerCompletely()
            pinchCandidateSince = pinchCandidateSince ?? now
            if now - (pinchCandidateSince ?? now) >= configuration.pinchActivationSeconds {
                pinchActive = true
                pinchMode = .undecided
                pinchStartPoint = point
                lastPinchPoint = point
                pinchNavigationTriggered = false
                output.append(.pinchBegan)
            }
            resetSwipe(released: true, at: now)
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
            return output
        }

        pinchCandidateSince = nil
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false

        if pointerModeEnabled {
            let pointerUpdate = updatePointer(pose: pose, at: now)
            output.append(contentsOf: pointerUpdate.output)
            if pointerUpdate.consumed {
                resetSwipe(released: true, at: now)
                output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
                return output
            }
        }

        let cannedGestureIsConfident =
            pose.gestureConfidence >= configuration.cannedGestureMinimumConfidence
        if cannedGestureIsConfident, pose.recognizedGesture == .thumbUp {
            resetSwipe(released: true, at: now)
            output.append(contentsOf: updateThumbsUp(isDetected: true, at: now))
            return output
        }

        if cannedGestureIsConfident,
           pose.recognizedGesture == .victory || pose.recognizedGesture == .pointingUp {
            resetSwipe(released: true, at: now)
            output.append(contentsOf: updateThumbsUp(isDetected: false, at: now))
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
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false
        thumbsUpCandidateSince = nil
        thumbsUpActive = false
        thumbsUpAbsentSince = nil
        endPointer(into: &output)
        resetPointerCompletely()
        resetSwipeCompletely()
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
        endPointer(into: &output)
        resetPointerCompletely()
        pinchCandidateSince = nil
        pinchMode = .inactive
        pinchStartPoint = nil
        lastPinchPoint = nil
        pinchNavigationTriggered = false
        resetSwipe(released: true, at: now)
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

    private func updateSwipe(pose: HandPose, at now: TimeInterval) -> [GestureOutput] {
        guard isOpenPalm(pose), let palm = palmCenter(pose) else {
            resetSwipe(released: true, at: now)
            return []
        }

        if !swipeArmed {
            if swipeReleaseObserved && now >= swipeCooldownUntil {
                rearmSwipe(with: palm, at: now)
            } else {
                let mirrored = SwipeSample(x: 1 - palm.x, y: palm.y, time: now)
                let movement = lastRearmPalm.map {
                    hypot(mirrored.x - $0.x, mirrored.y - $0.y)
                } ?? 0
                if lastRearmPalm == nil || movement > 0.018 {
                    swipeStableSince = now
                } else if swipeStableSince == nil {
                    swipeStableSince = now
                }
                lastRearmPalm = mirrored
                if let stableSince = swipeStableSince,
                   now - stableSince >= 0.18,
                   now >= swipeCooldownUntil {
                    rearmSwipe(with: palm, at: now)
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
              abs(deltaX) >= abs(deltaY) * configuration.horizontalDominance else { return [] }

        swipeArmed = false
        swipeReleaseObserved = false
        swipeCooldownUntil = now + configuration.swipeCooldownSeconds
        swipeSamples = []
        swipeStableSince = nil
        lastRearmPalm = SwipeSample(x: current.x, y: current.y, time: now)
        return [.page(deltaX < 0 ? .up : .down)]
    }

    private func updatePointer(
        pose: HandPose,
        at now: TimeInterval
    ) -> (output: [GestureOutput], consumed: Bool) {
        let pointerPose = isPointerInteractionPose(pose)
        let clickStrength = middleThumbPinchStrength(pose)
        let clickContact = pointerPose
            && isMiddleThumbContact(
                pose,
                threshold: configuration.pinchThreshold
            )
        let clickReleased = pointerPose
            && clickStrength >= configuration.pinchReleaseThreshold

        if pointerActive, pointerClickContactConsumed {
            guard clickReleased else { return ([], true) }
            pointerClickContactConsumed = false
        }

        if pointerActive, pointerClickReady, !pointerClickContactConsumed, clickContact {
            pointerClickContactCandidateSince = pointerClickContactCandidateSince ?? now
            guard now - (pointerClickContactCandidateSince ?? now)
                >= configuration.pinchActivationSeconds else {
                return ([], true)
            }
            pointerClickContactCandidateSince = nil
            pointerClickContactConsumed = true
            if let point = pointerLastPoint {
                return ([.pointerClicked(point)], true)
            }
            return ([], true)
        }
        if !clickContact {
            pointerClickContactCandidateSince = nil
        }

        let cannedPointing = pose.recognizedGesture == .pointingUp
            && pose.gestureConfidence >= configuration.cannedGestureMinimumConfidence
            && isStrictPointing(pose)
        let withinClassificationGrace = pointerActive
            && isStrictPointing(pose)
            && pointerLastConfirmedAt.map {
                now - $0 <= configuration.pointerClassificationGraceSeconds
            } == true
        let continuingClickPose = pointerActive
            && pointerPose
            && !isStrictPointing(pose)

        if cannedPointing || withinClassificationGrace || continuingClickPose,
           let point = pose.point(.indexTip).map(screenPoint) {
            if cannedPointing { pointerLastConfirmedAt = now }
            pointerCandidateSince = pointerCandidateSince ?? now

            if let previous = pointerLastPoint,
               pointDistance(previous, point) > configuration.pointerMaximumJump {
                pointerStableAnchor = point
                pointerStableSince = now
                pointerClickReady = false
                pointerClickContactCandidateSince = nil
                pointerLastPoint = point
                return ([], true)
            }

            pointerLastPoint = point
            if !pointerActive {
                guard now - (pointerCandidateSince ?? now) >= configuration.pointerActivationSeconds else {
                    return ([], true)
                }
                pointerActive = true
                pointerStableAnchor = point
                pointerStableSince = now
                pointerClickReady = false
                pointerClickContactCandidateSince = nil
            }

            if let anchor = pointerStableAnchor,
               pointDistance(anchor, point) <= configuration.pointerStableRadius {
                if now - (pointerStableSince ?? now) >= configuration.pointerStableSeconds {
                    pointerClickReady = true
                }
            } else {
                pointerStableAnchor = point
                pointerStableSince = now
                pointerClickReady = false
                pointerClickContactCandidateSince = nil
            }

            let state: PointerInteractionState = if pointerClickReady {
                pointerClickContactConsumed ? .clickReady : .clickArmed
            } else {
                .moving
            }
            return ([.pointerMoved(point, state)], true)
        }

        var output: [GestureOutput] = []
        endPointer(into: &output)
        resetPointerCompletely()
        return (output, false)
    }

    private func endPointer(into output: inout [GestureOutput]) {
        if pointerActive { output.append(.pointerEnded) }
        pointerActive = false
    }

    private func resetPointerCompletely() {
        pointerCandidateSince = nil
        pointerActive = false
        pointerLastConfirmedAt = nil
        pointerLastPoint = nil
        pointerStableAnchor = nil
        pointerStableSince = nil
        pointerClickReady = false
        pointerClickContactCandidateSince = nil
        pointerClickContactConsumed = false
    }

    private func resetSwipe(released: Bool, at now: TimeInterval) {
        swipeSamples = []
        if !swipeArmed && released {
            swipeReleaseObserved = true
            if now >= swipeCooldownUntil {
                resetSwipeCompletely()
            }
        }
    }

    private func resetSwipeCompletely() {
        swipeSamples = []
        swipeArmed = true
        swipeCooldownUntil = 0
        swipeReleaseObserved = false
        swipeStableSince = nil
        lastRearmPalm = nil
    }

    private func rearmSwipe(with palm: NormalizedPoint, at now: TimeInterval) {
        resetSwipeCompletely()
        swipeSamples = [SwipeSample(x: 1 - palm.x, y: palm.y, time: now)]
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
