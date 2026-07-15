import XCTest
@testable import GestureControlCore

final class GestureEngineTests: XCTestCase {
    private func makePose(
        palmX: Double = 0.5,
        thumbX: Double = 0.30,
        indexX: Double = 0.46,
        pinchY: Double = 0.50
    ) -> HandPose {
        HandPose(
            points: [
                .wrist: .init(x: palmX, y: 0.20),
                .thumbTip: .init(x: thumbX, y: pinchY),
                .indexMCP: .init(x: palmX - 0.09, y: 0.42),
                .indexTip: .init(x: indexX, y: pinchY),
                .middleMCP: .init(x: palmX - 0.03, y: 0.44),
                .middleTip: .init(x: palmX - 0.03, y: 0.82),
                .ringMCP: .init(x: palmX + 0.04, y: 0.43),
                .ringTip: .init(x: palmX + 0.04, y: 0.78),
                .littleMCP: .init(x: palmX + 0.10, y: 0.40),
                .littleTip: .init(x: palmX + 0.11, y: 0.70),
            ],
            confidence: 0.95
        )
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
}
