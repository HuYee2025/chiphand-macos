import AppKit
import AVFoundation
import Combine
import GestureControlCore
import OSLog
import QuartzCore

struct CenterCrossingFlash: Equatable, Identifiable {
    let id: UInt64
    let normalizedY: Double
}

@MainActor
final class AppModel: ObservableObject {
    private let logger = Logger(
        subsystem: "com.huyee.chiphand",
        category: "recognition"
    )
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var cameraPermission = PermissionService.cameraState
    @Published private(set) var accessibilityPermission = PermissionService.accessibilityState
    @Published private(set) var status = "已停止"
    @Published private(set) var handStatus = "等待启动"
    @Published private(set) var latestPose: HandPose?
    @Published private(set) var isPinching = false
    @Published private(set) var isThumbsUp = false
    @Published private(set) var recognitionFPS = 0
    @Published private(set) var inferenceDurationMS = 0.0
    @Published private(set) var recognitionEngine = "MediaPipe"
    @Published private(set) var centerCrossingFlash: CenterCrossingFlash?
    @Published var screenOverlayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(screenOverlayEnabled, forKey: "screenOverlayEnabled")
            if isRunning {
                screenOverlayController.show()
            } else if isPaused {
                screenOverlayController.showFeedbackOnly()
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
    @Published var pointerModeEnabled: Bool {
        didSet { pointerModeDidChange() }
    }
    @Published var controlHand: Handedness {
        didSet { controlHandDidChange() }
    }
    @Published private(set) var pointerInteractionState: PointerInteractionState?

    let camera = CameraCaptureService()

    private let handPoseService = HandPoseService()
    private let mediaPipeService = MediaPipeHandPoseService()
    private let gestureEngine = GestureEngine()
    private let emitter: ScrollEmitting = SystemScrollEmitter()
    private let navigationEmitter: NavigationEmitting = SystemNavigationEmitter()
    private let pointerEmitter: PointerEmitting = SystemPointerEmitter()
    private var processingFrame = false
    private var pinchTargetPID: pid_t?
    private var lastEligiblePID: pid_t?
    private var pendingStart = false
    private var workspaceObserver: NSObjectProtocol?
    private var permissionTimer: AnyCancellable?
    private var centerCrossingFlashTask: Task<Void, Never>?
    private var centerCrossingFlashSequence: UInt64 = 0
    private lazy var debugWindowController = DebugWindowController(model: self)
    private lazy var screenOverlayController = ScreenGestureOverlayController(model: self)
    private var actionFeedback: (message: String, until: TimeInterval)?
    private var usingAppleVisionFallback = false
    private var recognitionDelegate = "MediaPipe"
    private let navigationBrowserBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.quark.desktop",
    ]

    init() {
        let defaults = UserDefaults.standard
        controlHand = Handedness(rawValue: defaults.string(forKey: "controlHand") ?? "") ?? .right
        swipeSensitivity = defaults.object(forKey: "swipeSensitivity") as? Double ?? 50
        pinchSensitivity = defaults.object(forKey: "pinchSensitivity") as? Double ?? 50
        pointerModeEnabled = defaults.object(forKey: "pointerModeEnabled") as? Bool ?? false
        screenOverlayEnabled = defaults.object(forKey: "screenOverlayEnabled") as? Bool ?? true
        pointerInteractionState = nil
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
            self.recognitionDelegate = delegate
            self.recognitionEngine = delegate
            self.status = "手势控制中"
        }
        mediaPipeService.onPerformance = { [weak self] framesPerSecond, inferenceDuration in
            guard let self, !self.usingAppleVisionFallback else { return }
            self.recognitionFPS = framesPerSecond
            self.inferenceDurationMS = inferenceDuration
            self.recognitionEngine = "\(self.recognitionDelegate) · \(framesPerSecond) FPS"
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
        centerCrossingFlashTask?.cancel()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    var menuIcon: String {
        if isPaused { return "hand.raised.slash" }
        return isRunning ? "hand.raised.fill" : "hand.raised"
    }

    var showsPointingTip: Bool {
        guard pointerModeIsAvailable(),
              let latestPose else { return false }
        if pointerInteractionState != nil {
            return isPointerInteractionPose(latestPose)
        }
        return isPointingFingerConfiguration(latestPose)
    }

    var pointerClickContactPoint: NormalizedPoint? {
        guard pointerModeIsAvailable(),
              pointerInteractionState != nil,
              let latestPose,
              isPointerInteractionPose(latestPose),
              isMiddleThumbContact(
                  latestPose,
                  threshold: gestureEngine.configuration.pinchThreshold
              ) else { return nil }
        return middleThumbPinchCenter(latestPose)
    }

    var pointerMiddleThumbDistance: Double? {
        guard pointerModeIsAvailable(),
              pointerInteractionState != nil,
              let latestPose,
              isPointerInteractionPose(latestPose) else { return nil }
        return middleThumbPinchStrength(latestPose)
    }

    func toggle() {
        if isPaused {
            resume()
        } else if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        isPaused = false
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
        isPaused = false
        mediaPipeService.stop()
        usingAppleVisionFallback = false
        camera.stop()
        cancelCurrentGesture()
        latestPose = nil
        isPinching = false
        isThumbsUp = false
        recognitionFPS = 0
        inferenceDurationMS = 0
        debugWindowController.hide()
        screenOverlayController.hide()
        actionFeedback = nil
        handStatus = "等待启动"
        status = "已停止"
    }

    func togglePauseFromFeedback() {
        if isPaused {
            resume()
        } else if isRunning {
            pause()
        }
    }

    private func pause() {
        guard isRunning else { return }
        pendingStart = false
        isRunning = false
        isPaused = true
        mediaPipeService.stop()
        usingAppleVisionFallback = false
        camera.stop()
        cancelCurrentGesture()
        processingFrame = false
        latestPose = nil
        recognitionFPS = 0
        inferenceDurationMS = 0
        actionFeedback = nil
        debugWindowController.hide()
        recognitionEngine = recognitionDelegate + " · 已暂停"
        handStatus = "已暂停手势控制"
        status = "已暂停手势控制"
        screenOverlayController.showFeedbackOnly()
    }

    private func resume() {
        guard isPaused else { return }
        refreshPermissions()
        guard cameraPermission == .granted else {
            status = "摄像头权限已失效"
            handStatus = "已暂停 · 需要摄像头权限"
            return
        }
        guard accessibilityPermission == .granted else {
            status = "辅助功能权限已失效"
            handStatus = "已暂停 · 需要辅助功能权限"
            return
        }
        beginRunning()
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
        status = "请打开“薯片手”开关；授权后会自动启动"
    }

    func openUserGuide() {
        guard let guideURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "UserGuide"
        ) else {
            status = "未找到内置使用说明"
            return
        }
        NSWorkspace.shared.open(guideURL)
    }

    func testPageDown() {
        guard isRunning, !isPaused else {
            handStatus = isPaused ? "已暂停手势控制" : "手势控制未开启"
            return
        }
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
        let controlledPose = poseForControlHand(pose, controlHand: controlHand)
        if controlledPose == nil { clearCenterCrossingFlash() }
        let ignoredHand = pose?.handedness.flatMap { $0 == controlHand ? nil : $0 }
        latestPose = controlledPose
        let now = CACurrentMediaTime()
        let outputs = gestureEngine.update(
            pose: controlledPose,
            at: now,
            pointerModeEnabled: pointerModeIsAvailable()
        )
        isPinching = gestureEngine.isPinching()
        isThumbsUp = gestureEngine.isThumbsUpRecognized()
        for output in outputs { handle(output, at: now) }
        updateHandStatus(for: controlledPose, ignoredHand: ignoredHand, at: now)
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
                direction == .down ? "手掌右挥 · 已下翻" : "手掌左挥 · 已上翻",
                now + 0.8
            )
        case let .navigate(direction):
            triggerCenterCrossingFlash()
            guard browserNavigationTargetIsFrontmost() else {
                actionFeedback = (
                    direction == .back
                        ? "捏合右滑 · 当前应用不支持返回"
                        : "捏合左滑 · 当前应用不支持前进",
                    now + 0.9
                )
                return
            }
            navigationEmitter.emit(direction)
            actionFeedback = (
                direction == .back ? "已返回上一页" : "已前进下一页",
                now + 0.9
            )
        case let .pointerMoved(point, state):
            pointerEmitter.move(to: point)
            pointerInteractionState = state
        case let .pointerClicked(point):
            pointerEmitter.click(at: point)
            pointerInteractionState = .clickReady
            actionFeedback = ("已点击", now + 0.8)
        case .pointerClickRejected:
            pointerInteractionState = nil
            actionFeedback = ("请先稳定食指", now + 0.8)
        case .pointerEnded:
            pointerInteractionState = nil
        case .thumbsUpBegan:
            isThumbsUp = true
        case .thumbsUpEnded:
            isThumbsUp = false
        }
    }

    private func updateHandStatus(
        for pose: HandPose?,
        ignoredHand: Handedness?,
        at now: TimeInterval
    ) {
        if let feedback = actionFeedback, now < feedback.until {
            handStatus = feedback.message
            return
        }
        actionFeedback = nil

        guard let pose else {
            if let ignoredHand {
                handStatus = "已忽略\(handName(ignoredHand)) · 请使用\(handName(controlHand))"
            } else {
                handStatus = "等待\(handName(controlHand))"
            }
            return
        }
        let handPrefix = pose.handedness.map { handName($0) + " · " } ?? ""
        if isPinching {
            switch gestureEngine.pinchInteractionMode() {
            case .inactive, .undecided:
                handStatus = handPrefix + "已捏合 · 上下滚动，左右跨中线导航"
            case .scrolling:
                handStatus = handPrefix + (pinchTargetPID == nil
                    ? "已捏合 · 前台应用不可控制"
                    : "已捏合 · 上下移动滚动")
            case .navigation(.back):
                handStatus = handPrefix + "继续向右跨中线返回"
            case .navigation(.forward):
                handStatus = handPrefix + "继续向左跨中线前进"
            case .navigation(nil):
                handStatus = handPrefix + "请松开后从屏幕一侧重新捏合"
            }
            return
        }
        if isThumbsUp {
            handStatus = handPrefix + "👍 点赞手势已识别（测试模式）"
            return
        }
        if pointerModeEnabled, usingAppleVisionFallback,
           classifyHandShape(pose) == .pointing {
            handStatus = handPrefix + "备用识别模式 · 食指指针不可用"
            return
        }
        if pointerModeEnabled, classifyHandShape(pose) == .pointing,
           !browserNavigationTargetIsFrontmost() {
            handStatus = handPrefix + "当前应用不支持食指指针"
            return
        }
        if let distance = pointerMiddleThumbDistance,
           distance <= gestureEngine.configuration.pinchThreshold {
            handStatus = handPrefix + String(
                format: "已检测到拇指中指接触 · %.2f",
                distance
            )
            return
        }
        if pointerInteractionState == .clickArmed {
            let suffix = pointerMiddleThumbDistance.map {
                String(format: " · %.2f", $0)
            } ?? ""
            handStatus = handPrefix + "食指已定位 · 拇指中指轻捏点击" + suffix
            return
        }
        if pointerInteractionState == .clickReady {
            let suffix = pointerMiddleThumbDistance.map {
                String(format: " · %.2f", $0)
            } ?? ""
            handStatus = handPrefix + "已点击 · 松开后可再次点击" + suffix
            return
        }
        if pointerInteractionState == .moving {
            handStatus = handPrefix + "食指指针 · 移动鼠标"
            return
        }

        switch classifyHandShape(
            pose,
            pinchThreshold: gestureEngine.configuration.pinchThreshold
        ) {
        case .openPalm:
            handStatus = handPrefix + "张开手掌 · 左右挥动翻页"
        case .fist:
            handStatus = handPrefix + "已握拳 · 不执行操作"
        case .pointing:
            handStatus = handPrefix + (pointerModeEnabled
                ? "正在确认食指指针…"
                : "食指伸出 · 暂未设置操作")
        case .pinching:
            handStatus = handPrefix + "OK 手势·正在确认捏合…"
        case .victory:
            handStatus = handPrefix + "V 手势 · 暂未设置操作"
        case .thumbsUp:
            handStatus = handPrefix + "👍 正在确认点赞手势…"
        case .other:
            handStatus = handPrefix + "已识别手掌姿态"
        }
    }

    private func controlHandDidChange() {
        UserDefaults.standard.set(controlHand.rawValue, forKey: "controlHand")
        mediaPipeService.setControlHand(controlHand)
        cancelCurrentGesture()
        latestPose = nil
        actionFeedback = nil
        if isPaused {
            handStatus = "已暂停手势控制"
        } else if isRunning {
            handStatus = "已切换为\(handName(controlHand))控制 · 等待\(handName(controlHand))"
        }
    }

    private func handName(_ handedness: Handedness) -> String {
        handedness == .right ? "右手" : "左手"
    }

    private func browserNavigationTargetIsFrontmost() -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return navigationBrowserBundleIdentifiers.contains(bundleIdentifier)
    }

    private func pointerModeIsAvailable() -> Bool {
        pointerModeEnabled
            && !usingAppleVisionFallback
            && accessibilityPermission == .granted
            && browserNavigationTargetIsFrontmost()
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
        clearCenterCrossingFlash()
        pinchTargetPID = nil
        isPinching = false
        isThumbsUp = false
        pointerInteractionState = nil
    }

    private func triggerCenterCrossingFlash() {
        guard let latestPose,
              let center = pinchCenter(latestPose) else { return }
        centerCrossingFlashTask?.cancel()
        centerCrossingFlashSequence &+= 1
        let sequence = centerCrossingFlashSequence
        centerCrossingFlash = CenterCrossingFlash(
            id: sequence,
            normalizedY: center.y
        )
        centerCrossingFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled,
                  self?.centerCrossingFlash?.id == sequence else { return }
            self?.centerCrossingFlash = nil
            self?.centerCrossingFlashTask = nil
        }
    }

    private func clearCenterCrossingFlash() {
        centerCrossingFlashTask?.cancel()
        centerCrossingFlashTask = nil
        centerCrossingFlash = nil
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
        cancelCurrentGesture()
        latestPose = nil
        actionFeedback = nil
        usingAppleVisionFallback = true
        recognitionEngine = "Apple Vision 备用·新手势不可用"
        status = "MediaPipe 启动失败，已切换备用：\(message)"
        camera.start()
        if debugWindowEnabled { debugWindowController.show() }
    }

    private func beginRunning() {
        guard !isRunning else { return }
        pendingStart = false
        isPaused = false
        isRunning = true
        handStatus = "正在启动 MediaPipe…"
        status = "正在加载 MediaPipe…"
        recognitionEngine = "MediaPipe 启动中"
        recognitionDelegate = "MediaPipe"
        recognitionFPS = 0
        inferenceDurationMS = 0
        usingAppleVisionFallback = false
        mediaPipeService.setControlHand(controlHand)
        mediaPipeService.setPointerModeEnabled(pointerModeEnabled)
        mediaPipeService.start()
        mediaPipeService.setPreviewVisible(debugWindowEnabled)
        screenOverlayController.show()
    }

    private func saveAndApplySettings() {
        UserDefaults.standard.set(swipeSensitivity, forKey: "swipeSensitivity")
        UserDefaults.standard.set(pinchSensitivity, forKey: "pinchSensitivity")
        applySettings()
    }

    private func pointerModeDidChange() {
        UserDefaults.standard.set(pointerModeEnabled, forKey: "pointerModeEnabled")
        mediaPipeService.setPointerModeEnabled(pointerModeEnabled)
        cancelCurrentGesture()
        actionFeedback = nil
        if isRunning {
            handStatus = pointerModeEnabled
                ? "显示控制点已开启 · 等待\(handName(controlHand))"
                : "显示控制点已关闭"
        }
    }

    private func applySettings() {
        var configuration = gestureEngine.configuration
        configuration.swipeMinimumDisplacement = 0.22 - max(0, min(100, swipeSensitivity)) * 0.0012
        configuration.pinchThreshold = 0.12 + max(0, min(100, pinchSensitivity)) * 0.0012
        configuration.pinchReleaseThreshold = configuration.pinchThreshold + 0.02
        gestureEngine.configuration = configuration
    }
}
