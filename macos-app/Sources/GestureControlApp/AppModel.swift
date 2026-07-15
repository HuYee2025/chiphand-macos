import AppKit
import AVFoundation
import Combine
import GestureControlCore
import OSLog
import QuartzCore

@MainActor
final class AppModel: ObservableObject {
    private let logger = Logger(
        subsystem: "com.huyee.gesture-control.prototype",
        category: "recognition"
    )
    @Published private(set) var isRunning = false
    @Published private(set) var cameraPermission = PermissionService.cameraState
    @Published private(set) var accessibilityPermission = PermissionService.accessibilityState
    @Published private(set) var status = "已停止"
    @Published private(set) var handStatus = "等待启动"
    @Published private(set) var latestPose: HandPose?
    @Published private(set) var isPinching = false
    @Published private(set) var recognitionEngine = "MediaPipe"
    @Published var screenOverlayEnabled = true {
        didSet {
            if isRunning && screenOverlayEnabled {
                screenOverlayController.show()
            } else {
                screenOverlayController.hide()
            }
        }
    }
    @Published var debugWindowEnabled = false {
        didSet {
            guard isRunning else {
                debugWindowController.hide()
                return
            }
            if usingAppleVisionFallback {
                if debugWindowEnabled {
                    camera.start()
                    debugWindowController.show()
                } else {
                    debugWindowController.hide()
                }
            } else {
                debugWindowController.hide()
                camera.stop()
                mediaPipeService.setPreviewVisible(debugWindowEnabled)
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
    private let mediaPipeService = MediaPipeHandPoseService()
    private let gestureEngine = GestureEngine()
    private let emitter: ScrollEmitting = SystemScrollEmitter()
    private var processingFrame = false
    private var pinchTargetPID: pid_t?
    private var lastEligiblePID: pid_t?
    private var pendingStart = false
    private var workspaceObserver: NSObjectProtocol?
    private var permissionTimer: AnyCancellable?
    private lazy var debugWindowController = DebugWindowController(model: self)
    private lazy var screenOverlayController = ScreenGestureOverlayController(model: self)
    private var actionFeedback: (message: String, until: TimeInterval)?
    private var usingAppleVisionFallback = false

    init() {
        let defaults = UserDefaults.standard
        swipeSensitivity = defaults.object(forKey: "swipeSensitivity") as? Double ?? 50
        pinchSensitivity = defaults.object(forKey: "pinchSensitivity") as? Double ?? 50
        applySettings()
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastEligiblePID = application.processIdentifier
        }

        camera.onFrame = { [weak self] sampleBuffer in
            self?.process(sampleBuffer)
        }
        camera.onError = { [weak self] message in
            Task { @MainActor in self?.handleCameraError(message) }
        }
        mediaPipeService.onPose = { [weak self] pose in
            self?.consume(pose: pose)
        }
        mediaPipeService.onReady = { [weak self] delegate in
            guard let self, self.isRunning, !self.usingAppleVisionFallback else { return }
            self.logger.info("recognition ready: \(delegate, privacy: .public)")
            self.recognitionEngine = delegate
            self.status = "手势控制中"
        }
        mediaPipeService.onError = { [weak self] message in
            self?.handleMediaPipeError(message)
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                   application.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self.lastEligiblePID = application.processIdentifier
                }
                self.cancelCurrentGesture()
            }
        }
        permissionTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions() }
            }
        if ProcessInfo.processInfo.environment["GESTURE_CONTROL_DIAGNOSTIC_MEDIA"] == "1" {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.debugWindowEnabled = true
                self.beginRunning()
            }
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
        mediaPipeService.stop()
        usingAppleVisionFallback = false
        camera.stop()
        cancelCurrentGesture()
        latestPose = nil
        isPinching = false
        debugWindowController.hide()
        screenOverlayController.hide()
        actionFeedback = nil
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

    func testPageDown() {
        guard accessibilityPermission == .granted else {
            handStatus = "辅助功能未生效，无法发送滚动"
            return
        }
        guard let target = eligibleFrontmostPID() else {
            handStatus = "没有可控制的前台应用"
            return
        }
        emitter.emitPage(.down, to: target)
        handStatus = "测试下翻事件已发送"
        actionFeedback = ("测试下翻事件已发送", CACurrentMediaTime() + 0.8)
    }

    private nonisolated func process(_ sampleBuffer: CMSampleBuffer) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.isRunning,
                  self.usingAppleVisionFallback,
                  !self.processingFrame else { return }
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
        let now = CACurrentMediaTime()
        let outputs = gestureEngine.update(pose: pose, at: now)
        isPinching = gestureEngine.isPinching()
        for output in outputs { handle(output, at: now) }
        updateHandStatus(for: pose, at: now)
    }

    private func handle(_ output: GestureOutput, at now: TimeInterval) {
        switch output {
        case .pinchBegan:
            pinchTargetPID = eligibleFrontmostPID()
            if pinchTargetPID == nil {
                actionFeedback = ("已捏合 · 前台应用不可控制", now + 0.8)
            }
        case let .pinchScroll(delta):
            guard let target = pinchTargetPID else { return }
            emitter.emitContinuous(normalizedDelta: delta, to: target)
        case .pinchEnded:
            pinchTargetPID = nil
            handStatus = "已检测到手掌"
        case let .page(direction):
            guard let target = eligibleFrontmostPID() else { return }
            emitter.emitPage(direction, to: target)
            actionFeedback = (
                direction == .down ? "右挥 · 已下翻" : "左挥 · 已上翻",
                now + 0.8
            )
        }
    }

    private func updateHandStatus(for pose: HandPose?, at now: TimeInterval) {
        if let feedback = actionFeedback, now < feedback.until {
            handStatus = feedback.message
            return
        }
        actionFeedback = nil

        guard let pose else {
            handStatus = "未检测到手掌"
            return
        }
        let handName: String
        switch pose.handedness {
        case .left: handName = "左手 · "
        case .right: handName = "右手 · "
        case nil: handName = ""
        }
        if isPinching {
            handStatus = handName + (pinchTargetPID == nil
                ? "已捏合 · 前台应用不可控制"
                : "已捏合 · 上下移动滚动")
            return
        }

        switch classifyHandShape(
            pose,
            pinchThreshold: gestureEngine.configuration.pinchThreshold
        ) {
        case .openPalm:
            handStatus = handName + "张开手掌 · 左右挥动翻页"
        case .fist:
            handStatus = handName + "已握拳 · 不执行操作"
        case .pointing:
            handStatus = handName + "食指伸出 · 不执行操作"
        case .pinching:
            handStatus = handName + "正在确认捏合…"
        case .other:
            handStatus = handName + "已识别手掌姿态"
        }
    }

    private func eligibleFrontmostPID() -> pid_t? {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastEligiblePID = application.processIdentifier
            return application.processIdentifier
        }
        return lastEligiblePID
    }

    private func cancelCurrentGesture() {
        _ = gestureEngine.cancelActiveGesture()
        pinchTargetPID = nil
        isPinching = false
    }

    private func handleCameraError(_ message: String) {
        if usingAppleVisionFallback {
            stop()
            status = "摄像头错误：\(message)"
        } else {
            debugWindowEnabled = false
            status = "MediaPipe 控制中；校准窗口错误：\(message)"
        }
    }

    private func handleMediaPipeError(_ message: String) {
        guard isRunning, !usingAppleVisionFallback else { return }
        logger.error("MediaPipe error: \(message, privacy: .public)")
        mediaPipeService.stop()
        usingAppleVisionFallback = true
        recognitionEngine = "Apple Vision 备用"
        status = "MediaPipe 启动失败，已切换备用：\(message)"
        camera.start()
        if debugWindowEnabled { debugWindowController.show() }
    }

    private func beginRunning() {
        guard !isRunning else { return }
        pendingStart = false
        isRunning = true
        handStatus = "正在启动 MediaPipe…"
        status = "正在加载 MediaPipe…"
        recognitionEngine = "MediaPipe 启动中"
        usingAppleVisionFallback = false
        mediaPipeService.start()
        mediaPipeService.setPreviewVisible(debugWindowEnabled)
        if screenOverlayEnabled { screenOverlayController.show() }
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
