import AppKit
import AVFoundation
import Combine
import GestureControlCore
import QuartzCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var cameraPermission = PermissionService.cameraState
    @Published private(set) var accessibilityPermission = PermissionService.accessibilityState
    @Published private(set) var status = "已停止"
    @Published private(set) var handStatus = "等待启动"
    @Published private(set) var latestPose: HandPose?
    @Published var debugWindowEnabled = true {
        didSet {
            if isRunning && debugWindowEnabled {
                debugWindowController.show()
            } else {
                debugWindowController.hide()
            }
        }
    }
    @Published var swipeSensitivity: Double {
        didSet { saveAndApplySettings() }
    }
    @Published var pinchSensitivity: Double {
        didSet { saveAndApplySettings() }
    }

    let camera = CameraCaptureService()

    private let handPoseService = HandPoseService()
    private let gestureEngine = GestureEngine()
    private let emitter: ScrollEmitting = SystemScrollEmitter()
    private var processingFrame = false
    private var pinchTargetPID: pid_t?
    private var pendingStart = false
    private var workspaceObserver: NSObjectProtocol?
    private var permissionTimer: AnyCancellable?
    private lazy var debugWindowController = DebugWindowController(model: self)

    init() {
        let defaults = UserDefaults.standard
        swipeSensitivity = defaults.object(forKey: "swipeSensitivity") as? Double ?? 50
        pinchSensitivity = defaults.object(forKey: "pinchSensitivity") as? Double ?? 50
        applySettings()

        camera.onFrame = { [weak self] sampleBuffer in
            self?.process(sampleBuffer)
        }
        camera.onError = { [weak self] message in
            Task { @MainActor in self?.handleCameraError(message) }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancelCurrentGesture() }
        }
        permissionTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions() }
            }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    var menuIcon: String {
        isRunning ? "hand.raised.fill" : "hand.raised"
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        pendingStart = true
        status = "检查权限…"
        Task {
            let cameraGranted = await PermissionService.requestCamera()
            refreshPermissions()
            guard cameraGranted else {
                pendingStart = false
                status = "需要摄像头权限"
                return
            }
            guard accessibilityPermission == .granted else {
                status = "辅助功能未生效，请点下方“设置”"
                return
            }
            beginRunning()
        }
    }

    func stop() {
        pendingStart = false
        isRunning = false
        camera.stop()
        cancelCurrentGesture()
        latestPose = nil
        debugWindowController.hide()
        handStatus = "等待启动"
        status = "已停止"
    }

    func refreshPermissions() {
        cameraPermission = PermissionService.cameraState
        accessibilityPermission = PermissionService.accessibilityState
        if pendingStart,
           !isRunning,
           cameraPermission == .granted,
           accessibilityPermission == .granted {
            beginRunning()
        }
    }

    func openCameraSettings() {
        PermissionService.openCameraSettings()
    }

    func openAccessibilitySettings() {
        PermissionService.promptForAccessibility()
        PermissionService.openAccessibilitySettings()
        status = "请打开 GestureControl 开关；授权后会自动启动"
    }

    private nonisolated func process(_ sampleBuffer: CMSampleBuffer) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, !self.processingFrame else { return }
            self.processingFrame = true
            let service = self.handPoseService
            Task.detached(priority: .userInitiated) { [weak self] in
                let pose = try? service.detect(in: sampleBuffer)
                await self?.finishProcessing(pose)
            }
        }
    }

    private func finishProcessing(_ pose: HandPose?) {
        processingFrame = false
        consume(pose: pose)
    }

    private func consume(pose: HandPose?) {
        guard isRunning else { return }
        latestPose = pose
        handStatus = pose == nil ? "正在寻找手掌" : "已检测到手掌"
        let outputs = gestureEngine.update(pose: pose, at: CACurrentMediaTime())
        for output in outputs { handle(output) }
    }

    private func handle(_ output: GestureOutput) {
        switch output {
        case .pinchBegan:
            pinchTargetPID = eligibleFrontmostPID()
            handStatus = pinchTargetPID == nil ? "前台应用不可控制" : "已捏合 · 上下拖动"
        case let .pinchScroll(delta):
            guard let target = pinchTargetPID else { return }
            emitter.emitContinuous(normalizedDelta: delta, to: target)
        case .pinchEnded:
            pinchTargetPID = nil
            handStatus = "已检测到手掌"
        case let .page(direction):
            guard let target = eligibleFrontmostPID() else { return }
            emitter.emitPage(direction, to: target)
            handStatus = direction == .down ? "右挥 · 下翻" : "左挥 · 上翻"
        }
    }

    private func eligibleFrontmostPID() -> pid_t? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return application.processIdentifier
    }

    private func cancelCurrentGesture() {
        _ = gestureEngine.cancelActiveGesture()
        pinchTargetPID = nil
    }

    private func handleCameraError(_ message: String) {
        stop()
        status = "摄像头错误：\(message)"
    }

    private func beginRunning() {
        guard !isRunning else { return }
        pendingStart = false
        isRunning = true
        handStatus = "正在寻找手掌"
        status = "手势控制中"
        camera.start()
        if debugWindowEnabled { debugWindowController.show() }
    }

    private func saveAndApplySettings() {
        UserDefaults.standard.set(swipeSensitivity, forKey: "swipeSensitivity")
        UserDefaults.standard.set(pinchSensitivity, forKey: "pinchSensitivity")
        applySettings()
    }

    private func applySettings() {
        var configuration = gestureEngine.configuration
        configuration.swipeMinimumDisplacement = 0.22 - max(0, min(100, swipeSensitivity)) * 0.0012
        configuration.pinchThreshold = 0.12 + max(0, min(100, pinchSensitivity)) * 0.0012
        configuration.pinchReleaseThreshold = configuration.pinchThreshold + 0.02
        gestureEngine.configuration = configuration
    }
}
