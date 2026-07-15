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
    private var lastEligiblePID: pid_t?
    private var pendingStart = false
    private var workspaceObserver: NSObjectProtocol?
    private var permissionTimer: AnyCancellable?
    private lazy var debugWindowController = DebugWindowController(model: self)
    private lazy var screenOverlayController = ScreenGestureOverlayController(model: self)
    private var actionFeedback: (message: String, until: TimeInterval)?

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
        let now = CACurrentMediaTime()
        let outputs = gestureEngine.update(pose: pose, at: now)
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
        if gestureEngine.isPinching() {
            handStatus = pinchTargetPID == nil
                ? "已捏合 · 前台应用不可控制"
                : "已捏合 · 上下移动滚动"
            return
        }

        switch classifyHandShape(
            pose,
            pinchThreshold: gestureEngine.configuration.pinchThreshold
        ) {
        case .openPalm:
            handStatus = "张开手掌 · 左右挥动翻页"
        case .fist:
            handStatus = "已握拳 · 不执行操作"
        case .pointing:
            handStatus = "食指伸出 · 不执行操作"
        case .pinching:
            handStatus = "正在确认捏合…"
        case .other:
            handStatus = "已识别手掌姿态"
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
        if screenOverlayEnabled { screenOverlayController.show() }
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
