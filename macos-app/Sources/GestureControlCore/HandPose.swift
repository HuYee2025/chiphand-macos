import Foundation

public enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbCMC
    case thumbMP
    case thumbIP
    case thumbTip
    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip
    case middleMCP
    case middlePIP
    case middleDIP
    case middleTip
    case ringMCP
    case ringPIP
    case ringDIP
    case ringTip
    case littleMCP
    case littlePIP
    case littleDIP
    case littleTip
}

public enum HandShape: Equatable, Sendable {
    case openPalm
    case fist
    case pointing
    case pinching
    case victory
    case thumbsUp
    case other
}

public enum RecognizedGesture: String, Equatable, Sendable {
    case none = "None"
    case closedFist = "Closed_Fist"
    case openPalm = "Open_Palm"
    case pointingUp = "Pointing_Up"
    case thumbDown = "Thumb_Down"
    case thumbUp = "Thumb_Up"
    case victory = "Victory"
    case iLoveYou = "ILoveYou"
    case unknown = "Unknown"
}

public enum Handedness: String, CaseIterable, Identifiable, Equatable, Sendable {
    case left
    case right

    public var id: Self { self }
}

public struct NormalizedPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double = 1) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct HandPose: Equatable, Sendable {
    public var points: [HandJoint: NormalizedPoint]
    public var confidence: Double
    public var handedness: Handedness?
    public var recognizedGesture: RecognizedGesture
    public var gestureConfidence: Double
    public var inferenceDuration: TimeInterval

    public init(
        points: [HandJoint: NormalizedPoint],
        confidence: Double,
        handedness: Handedness? = nil,
        recognizedGesture: RecognizedGesture = .none,
        gestureConfidence: Double = 0,
        inferenceDuration: TimeInterval = 0
    ) {
        self.points = points
        self.confidence = confidence
        self.handedness = handedness
        self.recognizedGesture = recognizedGesture
        self.gestureConfidence = gestureConfidence
        self.inferenceDuration = inferenceDuration
    }

    public func point(_ joint: HandJoint) -> NormalizedPoint? {
        points[joint]
    }
}

public func poseForControlHand(
    _ pose: HandPose?,
    controlHand: Handedness
) -> HandPose? {
    guard let pose, pose.handedness == controlHand else { return nil }
    return pose
}

public func pointDistance(_ first: NormalizedPoint, _ second: NormalizedPoint) -> Double {
    hypot(first.x - second.x, first.y - second.y)
}

public func handScale(_ pose: HandPose) -> Double {
    guard let wrist = pose.point(.wrist) else { return 1 }
    let joints = [HandJoint.indexMCP, .middleMCP, .ringMCP, .littleMCP].compactMap(pose.point)
    guard !joints.isEmpty else { return 1 }
    return max(joints.reduce(0) { $0 + pointDistance(wrist, $1) } / Double(joints.count), 0.000_001)
}

public func pinchStrength(_ pose: HandPose) -> Double {
    guard let thumb = pose.point(.thumbTip), let index = pose.point(.indexTip) else {
        return .infinity
    }
    return pointDistance(thumb, index) / handScale(pose)
}

public func pinchCenter(_ pose: HandPose) -> NormalizedPoint? {
    guard let thumb = pose.point(.thumbTip), let index = pose.point(.indexTip) else { return nil }
    return NormalizedPoint(
        x: (thumb.x + index.x) / 2,
        y: (thumb.y + index.y) / 2,
        confidence: min(thumb.confidence, index.confidence)
    )
}

public func palmCenter(_ pose: HandPose) -> NormalizedPoint? {
    let joints = [HandJoint.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP].compactMap(pose.point)
    guard !joints.isEmpty else { return nil }
    return NormalizedPoint(
        x: joints.reduce(0) { $0 + $1.x } / Double(joints.count),
        y: joints.reduce(0) { $0 + $1.y } / Double(joints.count),
        confidence: joints.map(\.confidence).min() ?? 0
    )
}

public func isOpenPalm(_ pose: HandPose) -> Bool {
    guard let wrist = pose.point(.wrist) else { return false }
    let fingers: [(HandJoint, HandJoint)] = [
        (.indexTip, .indexMCP),
        (.middleTip, .middleMCP),
        (.ringTip, .ringMCP),
        (.littleTip, .littleMCP),
    ]
    return fingers.allSatisfy { tipJoint, mcpJoint in
        guard let tip = pose.point(tipJoint), let mcp = pose.point(mcpJoint) else { return false }
        return pointDistance(tip, wrist) > pointDistance(mcp, wrist) * 1.08
    }
}

public func isStrictPinch(_ pose: HandPose, pinchThreshold: Double = 0.20) -> Bool {
    guard pinchStrength(pose) <= pinchThreshold else { return false }
    return [
        fingerIsExtended(pose, tip: .middleTip, pip: .middlePIP, mcp: .middleMCP),
        fingerIsExtended(pose, tip: .ringTip, pip: .ringPIP, mcp: .ringMCP),
        fingerIsExtended(pose, tip: .littleTip, pip: .littlePIP, mcp: .littleMCP),
    ].allSatisfy { $0 == true }
}

public func isStrictPointing(_ pose: HandPose) -> Bool {
    guard fingerIsExtended(pose, tip: .indexTip, pip: .indexPIP, mcp: .indexMCP) == true,
          fingerIsExtended(pose, tip: .middleTip, pip: .middlePIP, mcp: .middleMCP) == false,
          fingerIsExtended(pose, tip: .ringTip, pip: .ringPIP, mcp: .ringMCP) == false,
          fingerIsExtended(pose, tip: .littleTip, pip: .littlePIP, mcp: .littleMCP) == false,
          thumbIsFoldedTowardPalm(pose) == true else { return false }
    return true
}

public func isPlausibleHandPose(_ pose: HandPose) -> Bool {
    guard pose.points.count >= 12,
          pose.point(.wrist) != nil else { return false }

    let fingerChains: [[HandJoint]] = [
        [.thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]
    let completeFingers = fingerChains.filter { chain in
        chain.allSatisfy { pose.point($0) != nil }
    }.count
    guard completeFingers >= 2 else { return false }

    let xs = pose.points.values.map(\.x)
    let ys = pose.points.values.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(),
          let minY = ys.min(), let maxY = ys.max() else { return false }
    // A side-on hand can be extremely narrow in one axis. Requiring both axes
    // to be wide rejected valid profile poses; a face false-positive cluster
    // remains small in every direction.
    return max(maxX - minX, maxY - minY) >= 0.08
}

public func classifyHandShape(_ pose: HandPose, pinchThreshold: Double = 0.20) -> HandShape {
    if isStrictPinch(pose, pinchThreshold: pinchThreshold) { return .pinching }
    if pose.gestureConfidence >= 0.70 {
        if pose.recognizedGesture == .pointingUp, isStrictPointing(pose) { return .pointing }
        if pose.recognizedGesture == .victory { return .victory }
        if pose.recognizedGesture == .thumbUp { return .thumbsUp }
    }

    let extended: [Bool?] = [
        fingerIsExtended(pose, tip: .indexTip, pip: .indexPIP, mcp: .indexMCP),
        fingerIsExtended(pose, tip: .middleTip, pip: .middlePIP, mcp: .middleMCP),
        fingerIsExtended(pose, tip: .ringTip, pip: .ringPIP, mcp: .ringMCP),
        fingerIsExtended(pose, tip: .littleTip, pip: .littlePIP, mcp: .littleMCP),
    ]

    let known = extended.compactMap { $0 }
    guard known.count >= 3 else { return .other }
    if known.allSatisfy({ $0 }) { return .openPalm }
    if isStrictPointing(pose) { return .pointing }
    if known.allSatisfy({ !$0 }) { return .fist }
    return .other
}

private func fingerIsExtended(
    _ pose: HandPose,
    tip: HandJoint,
    pip: HandJoint,
    mcp: HandJoint
) -> Bool? {
    guard let wrist = pose.point(.wrist),
          let tipPoint = pose.point(tip),
          let pipPoint = pose.point(pip),
          let mcpPoint = pose.point(mcp) else { return nil }
    let tipDistance = pointDistance(tipPoint, wrist)
    let pipDistance = pointDistance(pipPoint, wrist)
    let mcpDistance = pointDistance(mcpPoint, wrist)
    return tipDistance > pipDistance * 1.04 && tipDistance > mcpDistance * 1.12
}

private func thumbIsFoldedTowardPalm(_ pose: HandPose) -> Bool? {
    guard let tip = pose.point(.thumbTip) else { return nil }
    let palmAnchors = [
        HandJoint.indexMCP,
        .middleMCP,
        .ringMCP,
        .indexPIP,
        .middlePIP,
    ].compactMap(pose.point)
    guard let closestPalmDistance = palmAnchors.map({ pointDistance(tip, $0) }).min() else {
        return nil
    }
    return closestPalmDistance <= handScale(pose) * 0.90
}
