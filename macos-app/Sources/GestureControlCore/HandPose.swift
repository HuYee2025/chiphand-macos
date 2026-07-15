import Foundation

public enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbTip
    case indexMCP
    case indexTip
    case middleMCP
    case middleTip
    case ringMCP
    case ringTip
    case littleMCP
    case littleTip
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

    public init(points: [HandJoint: NormalizedPoint], confidence: Double) {
        self.points = points
        self.confidence = confidence
    }

    public func point(_ joint: HandJoint) -> NormalizedPoint? {
        points[joint]
    }
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
