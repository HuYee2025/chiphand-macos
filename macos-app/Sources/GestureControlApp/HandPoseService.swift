import CoreMedia
import ImageIO
import Vision
import GestureControlCore

final class HandPoseService: @unchecked Sendable {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private var selectedHandedness: Handedness?
    private var previousPose: HandPose?

    func detect(in sampleBuffer: CMSampleBuffer) throws -> HandPose? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        try handler.perform([request])
        let candidates = try (request.results ?? []).compactMap(makePose)
        guard !candidates.isEmpty else {
            selectedHandedness = nil
            previousPose = nil
            return nil
        }
        let preferred = candidates.first { $0.handedness == selectedHandedness }
        let pose = preferred ?? candidates.max { $0.confidence < $1.confidence } ?? candidates[0]
        selectedHandedness = pose.handedness
        let smoothed = smooth(pose)
        previousPose = smoothed
        return smoothed
    }

    private func makePose(_ observation: VNHumanHandPoseObservation) throws -> HandPose? {
        let recognized = try observation.recognizedPoints(.all)

        let mapping: [(HandJoint, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .wrist),
            (.thumbCMC, .thumbCMC),
            (.thumbMP, .thumbMP),
            (.thumbIP, .thumbIP),
            (.thumbTip, .thumbTip),
            (.indexMCP, .indexMCP),
            (.indexPIP, .indexPIP),
            (.indexDIP, .indexDIP),
            (.indexTip, .indexTip),
            (.middleMCP, .middleMCP),
            (.middlePIP, .middlePIP),
            (.middleDIP, .middleDIP),
            (.middleTip, .middleTip),
            (.ringMCP, .ringMCP),
            (.ringPIP, .ringPIP),
            (.ringDIP, .ringDIP),
            (.ringTip, .ringTip),
            (.littleMCP, .littleMCP),
            (.littlePIP, .littlePIP),
            (.littleDIP, .littleDIP),
            (.littleTip, .littleTip),
        ]

        var points: [HandJoint: GestureControlCore.NormalizedPoint] = [:]
        for (joint, visionJoint) in mapping {
            guard let point = recognized[visionJoint], point.confidence >= 0.25 else { continue }
            points[joint] = GestureControlCore.NormalizedPoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        let sortedConfidences = points.values.map(\.confidence).sorted()
        guard !sortedConfidences.isEmpty else { return nil }
        let confidence = sortedConfidences[sortedConfidences.count / 2]
        let handedness: Handedness?
        switch observation.chirality {
        case .left: handedness = .left
        case .right: handedness = .right
        default: handedness = nil
        }
        let pose = HandPose(points: points, confidence: confidence, handedness: handedness)
        return isPlausibleHandPose(pose) ? pose : nil
    }

    private func smooth(_ pose: HandPose) -> HandPose {
        guard let previousPose,
              previousPose.handedness == pose.handedness else { return pose }
        let alpha = 0.65
        var points = pose.points
        for (joint, point) in pose.points {
            guard let previous = previousPose.point(joint) else { continue }
            points[joint] = NormalizedPoint(
                x: previous.x + (point.x - previous.x) * alpha,
                y: previous.y + (point.y - previous.y) * alpha,
                confidence: point.confidence
            )
        }
        return HandPose(
            points: points,
            confidence: pose.confidence,
            handedness: pose.handedness
        )
    }
}
