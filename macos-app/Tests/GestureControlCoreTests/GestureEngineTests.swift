import XCTest
@testable import GestureControlCore

final class GestureEngineTests: XCTestCase {
    private func makePose(
        palmX: Double = 0.5,
        thumbX: Double = 0.30,
        indexX: Double = 0.46,
        pinchY: Double = 0.50,
        recognizedGesture: RecognizedGesture = .none,
        gestureConfidence: Double = 0,
        handedness: Handedness? = nil
    ) -> HandPose {
        HandPose(
            points: [
                .wrist: .init(x: palmX, y: 0.20),
                .thumbCMC: .init(x: palmX - 0.05, y: 0.31),
                .thumbMP: .init(x: palmX - 0.12, y: 0.38),
                .thumbIP: .init(x: (palmX - 0.12 + thumbX) / 2, y: (0.38 + pinchY) / 2),
                .thumbTip: .init(x: thumbX, y: pinchY),
                .indexMCP: .init(x: palmX - 0.09, y: 0.42),
                .indexPIP: .init(x: palmX - 0.09, y: 0.56),
                .indexDIP: .init(x: (palmX - 0.09 + indexX) / 2, y: 0.69),
                .indexTip: .init(x: indexX, y: pinchY),
                .middleMCP: .init(x: palmX - 0.03, y: 0.44),
                .middlePIP: .init(x: palmX - 0.03, y: 0.58),
                .middleDIP: .init(x: palmX - 0.03, y: 0.70),
                .middleTip: .init(x: palmX - 0.03, y: 0.82),
                .ringMCP: .init(x: palmX + 0.04, y: 0.43),
                .ringPIP: .init(x: palmX + 0.04, y: 0.56),
                .ringDIP: .init(x: palmX + 0.04, y: 0.67),
                .ringTip: .init(x: palmX + 0.04, y: 0.78),
                .littleMCP: .init(x: palmX + 0.10, y: 0.40),
                .littlePIP: .init(x: palmX + 0.105, y: 0.51),
                .littleDIP: .init(x: palmX + 0.108, y: 0.61),
                .littleTip: .init(x: palmX + 0.11, y: 0.70),
            ],
            confidence: 0.95,
            handedness: handedness,
            recognizedGesture: recognizedGesture,
            gestureConfidence: gestureConfidence
        )
    }

    private func makePinchPose(screenX: Double, y: Double = 0.50) -> HandPose {
        let rawX = 1 - screenX
        return makePose(
            palmX: rawX,
            thumbX: rawX - 0.01,
            indexX: rawX + 0.01,
            pinchY: y
        )
    }

    private func makeOpenPalmPose(screenX: Double) -> HandPose {
        makePose(palmX: 1 - screenX)
    }

    private func makePointingPose(
        screenTipX: Double,
        recognizedGesture: RecognizedGesture = .pointingUp,
        gestureConfidence: Double = 0.90
    ) -> HandPose {
        let pose = makePose(
            palmX: 0.50,
            indexX: 1 - screenTipX,
            pinchY: 0.82,
            recognizedGesture: recognizedGesture,
            gestureConfidence: gestureConfidence
        )
        var points = pose.points
        points[.thumbCMC] = .init(x: 0.45, y: 0.32)
        points[.thumbMP] = .init(x: 0.43, y: 0.36)
        points[.thumbIP] = .init(x: 0.44, y: 0.40)
        points[.thumbTip] = .init(x: 0.45, y: 0.37)
        for (tip, pip, x) in [
            (HandJoint.middleTip, HandJoint.middlePIP, 0.47),
            (.ringTip, .ringPIP, 0.54),
            (.littleTip, .littlePIP, 0.60),
        ] {
            points[pip] = .init(x: x, y: 0.43)
            points[tip] = .init(x: x, y: 0.34)
        }
        return HandPose(
            points: points,
            confidence: pose.confidence,
            recognizedGesture: recognizedGesture,
            gestureConfidence: gestureConfidence
        )
    }

    func testControlHandAcceptsOnlySelectedHand() {
        let rightPose = makePose(handedness: .right)
        let leftPose = makePose(handedness: .left)

        XCTAssertEqual(poseForControlHand(rightPose, controlHand: .right), rightPose)
        XCTAssertNil(poseForControlHand(leftPose, controlHand: .right))
        XCTAssertEqual(poseForControlHand(leftPose, controlHand: .left), leftPose)
        XCTAssertNil(poseForControlHand(rightPose, controlHand: .left))
    }

    func testControlHandRejectsUnknownHandedness() {
        XCTAssertNil(poseForControlHand(makePose(), controlHand: .right))
        XCTAssertNil(poseForControlHand(nil, controlHand: .left))
    }

    func testPinchRequiresStabilityAndEndsWhenHandIsLost() {
        let engine = GestureEngine()

        XCTAssertTrue(engine.update(pose: makePinchPose(screenX: 0.50), at: 0).isEmpty)
        XCTAssertEqual(
            engine.update(pose: makePinchPose(screenX: 0.50), at: 0.09),
            [.pinchBegan]
        )
        XCTAssertEqual(engine.pinchInteractionMode(), .undecided)

        let scroll = engine.update(
            pose: makePinchPose(screenX: 0.50, y: 0.56),
            at: 0.12
        )
        guard case let .pinchScroll(delta)? = scroll.first else {
            return XCTFail("稳定捏合移动应输出连续滚动")
        }
        XCTAssertEqual(delta, 0.06, accuracy: 0.000_001)
        XCTAssertEqual(engine.pinchInteractionMode(), .scrolling)
        XCTAssertEqual(engine.update(pose: nil, at: 0.13), [.pinchEnded])
        XCTAssertEqual(engine.pinchInteractionMode(), .inactive)
    }

    func testOpeningPinchEndsImmediately() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0)
        _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0.09)

        XCTAssertEqual(
            engine.update(pose: makePose(thumbX: 0.40, indexX: 0.60), at: 0.10),
            [.pinchEnded]
        )
    }

    func testVerticalPinchLockIgnoresHorizontalDrift() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePinchPose(screenX: 0.30), at: 0)
        _ = engine.update(pose: makePinchPose(screenX: 0.30), at: 0.09)
        _ = engine.update(pose: makePinchPose(screenX: 0.30, y: 0.54), at: 0.12)

        let output = engine.update(pose: makePinchPose(screenX: 0.55, y: 0.55), at: 0.20)
        XCTAssertEqual(engine.pinchInteractionMode(), .scrolling)
        XCTAssertFalse(output.contains(.navigate(.back)))
    }

    func testPinchLeftToRightAcrossCenterNavigatesBackOnce() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePinchPose(screenX: 0.30), at: 0)
        XCTAssertEqual(engine.update(pose: makePinchPose(screenX: 0.30), at: 0.09), [.pinchBegan])
        XCTAssertTrue(engine.update(pose: makePinchPose(screenX: 0.38), at: 0.12).isEmpty)
        XCTAssertEqual(engine.pinchInteractionMode(), .navigation(.back))
        XCTAssertTrue(
            engine.update(pose: makePinchPose(screenX: 0.40, y: 0.66), at: 0.16).isEmpty
        )
        XCTAssertEqual(engine.pinchInteractionMode(), .navigation(.back))
        XCTAssertEqual(
            engine.update(pose: makePinchPose(screenX: 0.55), at: 0.20),
            [.navigate(.back)]
        )
        XCTAssertTrue(engine.update(pose: makePinchPose(screenX: 0.62), at: 0.24).isEmpty)
    }

    func testPinchRightToLeftAcrossCenterNavigatesForwardOnce() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePinchPose(screenX: 0.70), at: 0)
        _ = engine.update(pose: makePinchPose(screenX: 0.70), at: 0.09)
        _ = engine.update(pose: makePinchPose(screenX: 0.62), at: 0.12)
        XCTAssertEqual(engine.pinchInteractionMode(), .navigation(.forward))
        XCTAssertEqual(
            engine.update(pose: makePinchPose(screenX: 0.48), at: 0.20),
            [.navigate(.forward)]
        )
        XCTAssertTrue(engine.update(pose: makePinchPose(screenX: 0.38), at: 0.24).isEmpty)
    }

    func testPinchNearCenterAndDiagonalMovementDoNotNavigateOrScroll() {
        let nearCenter = GestureEngine()
        _ = nearCenter.update(pose: makePinchPose(screenX: 0.48), at: 0)
        _ = nearCenter.update(pose: makePinchPose(screenX: 0.48), at: 0.09)
        XCTAssertTrue(nearCenter.update(pose: makePinchPose(screenX: 0.68), at: 0.20).isEmpty)
        XCTAssertEqual(nearCenter.pinchInteractionMode(), .navigation(nil))

        let diagonal = GestureEngine()
        _ = diagonal.update(pose: makePinchPose(screenX: 0.30), at: 0)
        _ = diagonal.update(pose: makePinchPose(screenX: 0.30), at: 0.09)
        XCTAssertTrue(
            diagonal.update(pose: makePinchPose(screenX: 0.48, y: 0.70), at: 0.20).isEmpty
        )
        XCTAssertEqual(diagonal.pinchInteractionMode(), .undecided)
    }

    func testCancellationEndsPinchAndClearsSwipeTrail() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0)
        _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0.09)

        XCTAssertEqual(engine.cancelActiveGesture(), [.pinchEnded])
        XCTAssertTrue(engine.update(pose: makePose(palmX: 0.40), at: 0.10).isEmpty)
    }

    func testRejectsSparseFaceLikePointCloud() {
        let sparse = HandPose(
            points: [
                .wrist: .init(x: 0.50, y: 0.50),
                .thumbTip: .init(x: 0.52, y: 0.51),
                .indexTip: .init(x: 0.53, y: 0.52),
                .middleTip: .init(x: 0.54, y: 0.51),
            ],
            confidence: 0.90
        )

        XCTAssertFalse(isPlausibleHandPose(sparse))
    }

    func testRecognizesOpenPalmAndFist() {
        let openPalm = makePose(indexX: 0.41, pinchY: 0.82)
        XCTAssertTrue(isPlausibleHandPose(openPalm))
        XCTAssertEqual(classifyHandShape(openPalm), .openPalm)

        var fistPoints = openPalm.points
        for (tip, pip, x) in [
            (HandJoint.indexTip, HandJoint.indexPIP, 0.41),
            (.middleTip, .middlePIP, 0.47),
            (.ringTip, .ringPIP, 0.54),
            (.littleTip, .littlePIP, 0.60),
        ] {
            fistPoints[pip] = .init(x: x, y: 0.43)
            fistPoints[tip] = .init(x: x, y: 0.34)
        }
        let fist = HandPose(points: fistPoints, confidence: 0.95)
        XCTAssertEqual(classifyHandShape(fist), .fist)
    }

    func testFistWithCloseThumbAndIndexDoesNotStartPinch() {
        var points = makePose(thumbX: 0.49, indexX: 0.51).points
        for (tip, pip, x) in [
            (HandJoint.middleTip, HandJoint.middlePIP, 0.47),
            (.ringTip, .ringPIP, 0.54),
            (.littleTip, .littlePIP, 0.60),
        ] {
            points[pip] = .init(x: x, y: 0.43)
            points[tip] = .init(x: x, y: 0.34)
        }
        let fistLikePinch = HandPose(points: points, confidence: 0.95)

        XCTAssertFalse(isStrictPinch(fistLikePinch, pinchThreshold: 0.18))
        let engine = GestureEngine()
        XCTAssertTrue(engine.update(pose: fistLikePinch, at: 0).isEmpty)
        XCTAssertTrue(engine.update(pose: fistLikePinch, at: 0.10).isEmpty)
        XCTAssertFalse(engine.isPinching())
    }

    func testOpenPalmRightSwipePagesDownWithoutCrossingCenter() {
        let engine = GestureEngine()
        XCTAssertTrue(engine.update(pose: makeOpenPalmPose(screenX: 0.20), at: 0).isEmpty)
        XCTAssertEqual(
            engine.update(pose: makeOpenPalmPose(screenX: 0.38), at: 0.14),
            [.page(.down)]
        )
    }

    func testOpenPalmLeftSwipePagesUpWithoutCrossingCenter() {
        let engine = GestureEngine()
        XCTAssertTrue(engine.update(pose: makeOpenPalmPose(screenX: 0.80), at: 0).isEmpty)
        XCTAssertEqual(
            engine.update(pose: makeOpenPalmPose(screenX: 0.62), at: 0.14),
            [.page(.up)]
        )
    }

    func testOpenPalmSwipeEmitsOnlyOnceDuringCooldown() {
        let engine = GestureEngine()
        _ = engine.update(pose: makeOpenPalmPose(screenX: 0.20), at: 0)
        XCTAssertEqual(engine.update(pose: makeOpenPalmPose(screenX: 0.38), at: 0.14), [.page(.down)])
        XCTAssertTrue(engine.update(pose: makeOpenPalmPose(screenX: 0.60), at: 0.30).isEmpty)
    }

    func testStrictPointingRequiresAClosedHandAroundTheIndexFinger() {
        let strict = makePointingPose(
            screenTipX: 0.50,
            recognizedGesture: .none,
            gestureConfidence: 0
        )
        XCTAssertTrue(isStrictPointing(strict))

        let openPalm = makePose(indexX: 0.50, pinchY: 0.82)
        XCTAssertFalse(isStrictPointing(openPalm))

        var openThumbPoints = strict.points
        openThumbPoints[.thumbMP] = .init(x: 0.40, y: 0.40)
        openThumbPoints[.thumbIP] = .init(x: 0.31, y: 0.52)
        openThumbPoints[.thumbTip] = .init(x: 0.20, y: 0.68)
        let openThumb = HandPose(points: openThumbPoints, confidence: 0.95)
        XCTAssertFalse(isStrictPointing(openThumb))
    }

    func testOpenPalmSwipeRearmsAfterReleaseAndCooldown() {
        let engine = GestureEngine()
        _ = engine.update(pose: makeOpenPalmPose(screenX: 0.20), at: 0)
        XCTAssertEqual(engine.update(pose: makeOpenPalmPose(screenX: 0.38), at: 0.14), [.page(.down)])
        XCTAssertTrue(engine.update(pose: makePointingPose(screenTipX: 0.50), at: 0.20).isEmpty)
        XCTAssertTrue(engine.update(pose: makeOpenPalmPose(screenX: 0.20), at: 0.80).isEmpty)
        XCTAssertEqual(engine.update(pose: makeOpenPalmPose(screenX: 0.38), at: 0.95), [.page(.down)])
    }

    func testVictoryIsReservedAndNeverPages() {
        let engine = GestureEngine()
        let left = makePose(
            palmX: 0.70,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        let right = makePose(
            palmX: 0.30,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        XCTAssertTrue(engine.update(pose: left, at: 0).isEmpty)
        XCTAssertTrue(engine.update(pose: left, at: 0.23).isEmpty)
        XCTAssertTrue(engine.update(pose: right, at: 0.40).isEmpty)
    }

    func testPointingNeverPages() {
        let engine = GestureEngine()
        XCTAssertTrue(engine.update(pose: makePointingPose(screenTipX: 0.20), at: 0).isEmpty)
        XCTAssertTrue(engine.update(pose: makePointingPose(screenTipX: 0.80), at: 0.20).isEmpty)
    }

    func testThumbsUpIsStatusOnlyAndUsesStableActivation() {
        let engine = GestureEngine()
        let thumbsUp = makePose(
            recognizedGesture: .thumbUp,
            gestureConfidence: 0.90
        )
        XCTAssertTrue(engine.update(pose: thumbsUp, at: 0).isEmpty)
        XCTAssertEqual(engine.update(pose: thumbsUp, at: 0.31), [.thumbsUpBegan])
        XCTAssertTrue(engine.isThumbsUpRecognized())

        XCTAssertTrue(engine.update(pose: makePose(), at: 0.40).isEmpty)
        XCTAssertEqual(engine.update(pose: makePose(), at: 0.56), [.thumbsUpEnded])
        XCTAssertFalse(engine.isThumbsUpRecognized())
    }
}
