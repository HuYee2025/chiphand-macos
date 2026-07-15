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

        XCTAssertTrue(engine.update(pose: makePose(thumbX: 0.49, indexX: 0.51), at: 0).isEmpty)
        XCTAssertEqual(
            engine.update(pose: makePose(thumbX: 0.49, indexX: 0.51), at: 0.09),
            [.pinchBegan]
        )

        let scroll = engine.update(
            pose: makePose(thumbX: 0.49, indexX: 0.51, pinchY: 0.56),
            at: 0.12
        )
        guard case let .pinchScroll(delta)? = scroll.first else {
            return XCTFail("稳定捏合移动应输出连续滚动")
        }
        XCTAssertEqual(delta, 0.06, accuracy: 0.000_001)
        XCTAssertEqual(engine.update(pose: nil, at: 0.13), [.pinchEnded])
    }

    func testOpeningPinchEndsImmediately() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePose(thumbX: 0.49, indexX: 0.51), at: 0)
        _ = engine.update(pose: makePose(thumbX: 0.49, indexX: 0.51), at: 0.09)

        XCTAssertEqual(
            engine.update(pose: makePose(thumbX: 0.40, indexX: 0.60), at: 0.10),
            [.pinchEnded]
        )
    }

    func testPhysicalRightSwipePagesDown() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePose(palmX: 0.65), at: 0)

        XCTAssertEqual(engine.update(pose: makePose(palmX: 0.45), at: 0.14), [.page(.down)])
    }

    func testPhysicalLeftSwipePagesUp() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePose(palmX: 0.35), at: 0)

        XCTAssertEqual(engine.update(pose: makePose(palmX: 0.55), at: 0.14), [.page(.up)])
    }

    func testCancellationEndsPinchAndClearsSwipeTrail() {
        let engine = GestureEngine()
        _ = engine.update(pose: makePose(thumbX: 0.49, indexX: 0.51), at: 0)
        _ = engine.update(pose: makePose(thumbX: 0.49, indexX: 0.51), at: 0.09)

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

    func testVictoryMustStabilizeThenMovePhysicalLeftToGoBack() {
        let engine = GestureEngine()
        let victoryAtStart = makePose(
            palmX: 0.35,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        XCTAssertTrue(engine.update(pose: victoryAtStart, at: 0).isEmpty)
        XCTAssertTrue(engine.update(pose: victoryAtStart, at: 0.23).isEmpty)

        let victoryMovedLeft = makePose(
            palmX: 0.50,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        XCTAssertEqual(engine.update(pose: victoryMovedLeft, at: 0.40), [.back])
        XCTAssertTrue(engine.update(pose: victoryMovedLeft, at: 0.50).isEmpty)
    }

    func testStaticVictoryDoesNotGoBack() {
        let engine = GestureEngine()
        let victory = makePose(
            palmX: 0.45,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        XCTAssertTrue(engine.update(pose: victory, at: 0).isEmpty)
        XCTAssertTrue(engine.update(pose: victory, at: 0.23).isEmpty)
        XCTAssertTrue(engine.update(pose: victory, at: 0.50).isEmpty)
        XCTAssertTrue(engine.update(pose: victory, at: 0.90).isEmpty)
    }

    func testBackRequiresReleaseAndCooldownBeforeItCanRepeat() {
        let engine = GestureEngine()
        let start = makePose(
            palmX: 0.35,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        let moved = makePose(
            palmX: 0.50,
            recognizedGesture: .victory,
            gestureConfidence: 0.90
        )
        _ = engine.update(pose: start, at: 0)
        _ = engine.update(pose: start, at: 0.23)
        XCTAssertEqual(engine.update(pose: moved, at: 0.40), [.back])

        XCTAssertTrue(engine.update(pose: makePose(), at: 0.50).isEmpty)
        XCTAssertTrue(engine.update(pose: makePose(), at: 0.66).isEmpty)
        XCTAssertTrue(engine.update(pose: start, at: 1.26).isEmpty)
        XCTAssertTrue(engine.update(pose: start, at: 1.49).isEmpty)
        XCTAssertEqual(engine.update(pose: moved, at: 1.66), [.back])
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
