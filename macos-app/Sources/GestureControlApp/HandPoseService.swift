import CoreMedia
import ImageIO
import Vision
import GestureControlCore

final class HandPoseService: @unchecked Sendable {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()

    func detect(in sampleBuffer: CMSampleBuffer) throws -> HandPose? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        let recognized = try observation.recognizedPoints(.all)

        let mapping: [(HandJoint, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .wrist),
            (.thumbTip, .thumbTip),
            (.indexMCP, .indexMCP),
            (.indexTip, .indexTip),
            (.middleMCP, .middleMCP),
            (.middleTip, .middleTip),
            (.ringMCP, .ringMCP),
            (.ringTip, .ringTip),
            (.littleMCP, .littleMCP),
            (.littleTip, .littleTip),
        ]

        var points: [HandJoint: GestureControlCore.NormalizedPoint] = [:]
        for (joint, visionJoint) in mapping {
            guard let point = recognized[visionJoint], point.confidence >= 0.35 else { continue }
            points[joint] = GestureControlCore.NormalizedPoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        guard points[.wrist] != nil else { return nil }
        let confidence = points.values.map(\.confidence).min() ?? 0
        return HandPose(points: points, confidence: confidence)
    }
}
