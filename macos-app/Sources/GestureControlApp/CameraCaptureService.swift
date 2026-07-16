@preconcurrency import AVFoundation
import Foundation

final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onFrame: (@Sendable (CMSampleBuffer) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.huyee.chiphand.camera")
    private let frameQueue = DispatchQueue(label: "com.huyee.chiphand.frames", qos: .userInteractive)
    private var configured = false

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
            } catch {
                self.onError?(error.localizedDescription)
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw CameraError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: frameQueue)

        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }

    private enum CameraError: LocalizedError {
        case cameraUnavailable
        case configurationFailed

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: "没有找到可用摄像头。"
            case .configurationFailed: "摄像头输入或输出配置失败。"
            }
        }
    }
}
