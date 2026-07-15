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
            guard let point = recognized[visionJoint], point.confidence >= 0.35 else { continue }
            points[joint] = GestureControlCore.NormalizedPoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        let sortedConfidences = points.values.map(\.confidence).sorted()
        guard !sortedConfidences.isEmpty else { return nil }
        let confidence = sortedConfidences[sortedConfidences.count / 2]
        let pose = HandPose(points: points, confidence: confidence)
        return isPlausibleHandPose(pose) ? pose : nil
    }
}
