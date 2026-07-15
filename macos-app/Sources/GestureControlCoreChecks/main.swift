import Foundation
import GestureControlCore

private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() {
        print("✓ \(name)")
    } else {
        failures.append(name)
        print("✗ \(name)")
    }
}

private func makePose(
    palmX: Double = 0.5,
    thumbX: Double = 0.30,
    indexX: Double = 0.46,
    pinchY: Double = 0.50,
    recognizedGesture: RecognizedGesture = .none,
    gestureConfidence: Double = 0
) -> HandPose {
    let points: [HandJoint: NormalizedPoint] = [
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
    ]
    return HandPose(
        points: points,
        confidence: 0.95,
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

private func makePointingPose(screenX: Double) -> HandPose {
    makePose(
        palmX: 1 - screenX,
        recognizedGesture: .pointingUp,
        gestureConfidence: 0.90
    )
}

do {
    let engine = GestureEngine()
    check(engine.update(pose: makePinchPose(screenX: 0.50), at: 0).isEmpty, "捏合需要稳定时间")
    check(engine.update(pose: makePinchPose(screenX: 0.50), at: 0.09) == [.pinchBegan], "稳定捏合开始")
    let scroll = engine.update(pose: makePinchPose(screenX: 0.50, y: 0.56), at: 0.12)
    if case let .pinchScroll(delta)? = scroll.first {
        check(abs(delta - 0.06) < 0.000_001, "捏合上下移动输出连续滚动")
    } else {
        check(false, "捏合上下移动输出连续滚动")
    }
    check(engine.update(pose: nil, at: 0.13) == [.pinchEnded], "丢手立即停止捏合")
}

do {
    let engine = GestureEngine()
    _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0)
    _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0.09)
    check(engine.update(pose: makePose(thumbX: 0.40, indexX: 0.60), at: 0.10) == [.pinchEnded], "松开立即停止捏合")
}

do {
    let engine = GestureEngine()
    _ = engine.update(pose: makePinchPose(screenX: 0.30), at: 0)
    _ = engine.update(pose: makePinchPose(screenX: 0.30), at: 0.09)
    _ = engine.update(pose: makePinchPose(screenX: 0.38), at: 0.12)
    check(
        engine.update(pose: makePinchPose(screenX: 0.52), at: 0.20) == [.navigate(.back)],
        "捏合向右跨中线返回"
    )
}

do {
    let engine = GestureEngine()
    _ = engine.update(pose: makePinchPose(screenX: 0.70), at: 0)
    _ = engine.update(pose: makePinchPose(screenX: 0.70), at: 0.09)
    _ = engine.update(pose: makePinchPose(screenX: 0.62), at: 0.12)
    check(
        engine.update(pose: makePinchPose(screenX: 0.48), at: 0.20) == [.navigate(.forward)],
        "捏合向左跨中线前进"
    )
}

do {
    let engine = GestureEngine()
    let start = makePointingPose(screenX: 0.30)
    _ = engine.update(pose: start, at: 0)
    _ = engine.update(pose: start, at: 0.23)
    check(engine.update(pose: makePointingPose(screenX: 0.52), at: 0.40) == [.page(.down)], "食指右滑映射下翻")
}

do {
    let engine = GestureEngine()
    let start = makePointingPose(screenX: 0.70)
    _ = engine.update(pose: start, at: 0)
    _ = engine.update(pose: start, at: 0.23)
    check(engine.update(pose: makePointingPose(screenX: 0.48), at: 0.40) == [.page(.up)], "食指左滑映射上翻")
    check(engine.update(pose: makePose(palmX: 0.20), at: 0.60).isEmpty, "张开手掌不再翻页")
}

do {
    let engine = GestureEngine()
    let victory = makePose(recognizedGesture: .victory, gestureConfidence: 0.90)
    _ = engine.update(pose: victory, at: 0)
    _ = engine.update(pose: victory, at: 0.23)
    check(engine.update(pose: victory, at: 0.40).isEmpty, "V 手势保留但不执行操作")
}

do {
    let engine = GestureEngine()
    _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0)
    _ = engine.update(pose: makePinchPose(screenX: 0.50), at: 0.09)
    check(engine.cancelActiveGesture() == [.pinchEnded], "切换应用取消当前捏合")
    check(engine.update(pose: makePose(palmX: 0.40), at: 0.10).isEmpty, "取消后清空方向锁")
}

if !failures.isEmpty {
    fputs("\n核心检查失败：\(failures.joined(separator: "、"))\n", stderr)
    exit(1)
}

print("\n全部核心检查通过。")
