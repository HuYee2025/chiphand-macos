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

private func makeMiddleThumbClickPose(
    screenTipX: Double,
    touching: Bool
) -> HandPose {
    let pointing = makePointingPose(
        screenTipX: screenTipX,
        recognizedGesture: .none,
        gestureConfidence: 0
    )
    var points = pointing.points
    points[.thumbMP] = .init(x: 0.40, y: 0.42)
    points[.thumbIP] = .init(x: touching ? 0.34 : 0.28, y: 0.50)
    points[.thumbTip] = .init(x: touching ? 0.31 : 0.20, y: touching ? 0.56 : 0.55)
    points[.middlePIP] = .init(x: 0.47, y: 0.46)
    points[.middleTip] = .init(x: touching ? 0.30 : 0.55, y: touching ? 0.55 : 0.65)
    return HandPose(points: points, confidence: pointing.confidence)
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
    _ = engine.update(pose: makeOpenPalmPose(screenX: 0.20), at: 0)
    check(engine.update(pose: makeOpenPalmPose(screenX: 0.38), at: 0.14) == [.page(.down)], "张开手掌右挥映射下翻")
}

do {
    let engine = GestureEngine()
    _ = engine.update(pose: makeOpenPalmPose(screenX: 0.80), at: 0)
    check(engine.update(pose: makeOpenPalmPose(screenX: 0.62), at: 0.14) == [.page(.up)], "张开手掌左挥映射上翻")
}

do {
    let engine = GestureEngine()
    let start = makePointingPose(screenTipX: 0.30)
    _ = engine.update(pose: start, at: 0)
    check(engine.update(pose: makePointingPose(screenTipX: 0.70), at: 0.20).isEmpty, "食指左右移动不再翻页")
    check(isStrictPointing(start), "食指姿态要求其余手指收拢")
}

do {
    let engine = GestureEngine()
    let pointing = makePointingPose(screenTipX: 0.42)
    let separated = makeMiddleThumbClickPose(screenTipX: 0.42, touching: false)
    let touching = makeMiddleThumbClickPose(screenTipX: 0.42, touching: true)
    check(
        isMiddleThumbContact(touching, threshold: engine.configuration.pinchThreshold)
            && !isMiddleThumbContact(separated, threshold: engine.configuration.pinchThreshold),
        "拇指中指复用 OK 捏合距离阈值"
    )
    check(
        engine.update(pose: pointing, at: 0, pointerModeEnabled: true).isEmpty,
        "食指指针需要稳定激活"
    )
    let moving = engine.update(pose: pointing, at: 0.16, pointerModeEnabled: true)
    if case .pointerMoved(_, .moving)? = moving.first {
        check(true, "稳定食指开始移动鼠标")
    } else {
        check(false, "稳定食指开始移动鼠标")
    }
    let ready = engine.update(pose: pointing, at: 0.52, pointerModeEnabled: true)
    if case .pointerMoved(_, .clickArmed)? = ready.first {
        check(true, "食指停稳后可直接拇指中指捏合")
    } else {
        check(false, "食指停稳后可直接拇指中指捏合")
    }
    check(engine.update(pose: touching, at: 0.60, pointerModeEnabled: true).isEmpty,
          "拇指中指接触需要短暂稳定")
    let click = engine.update(
        pose: touching,
        at: 0.69,
        pointerModeEnabled: true
    )
    if click.count == 1, case .pointerClicked = click[0] {
        check(true, "食指定位后拇指中指接触输出单击")
    } else {
        check(false, "食指定位后拇指中指接触输出单击")
    }
}

do {
    let engine = GestureEngine()
    let pointing = makePointingPose(screenTipX: 0.42)
    let touching = makeMiddleThumbClickPose(screenTipX: 0.42, touching: true)
    _ = engine.update(pose: pointing, at: 0, pointerModeEnabled: true)
    _ = engine.update(pose: pointing, at: 0.16, pointerModeEnabled: true)
    let early = engine.update(pose: touching, at: 0.20, pointerModeEnabled: true)
    let held = engine.update(pose: touching, at: 0.33, pointerModeEnabled: true)
    check(!early.contains { if case .pointerClicked = $0 { true } else { false } },
          "食指尚未停稳时不点击")
    check(!held.contains { if case .pointerClicked = $0 { true } else { false } },
          "持续接触不会误点击")
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
