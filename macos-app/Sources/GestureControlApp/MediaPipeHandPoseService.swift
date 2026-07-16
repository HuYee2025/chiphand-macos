import AppKit
import GestureControlCore
import OSLog
import WebKit

@MainActor
final class MediaPipeHandPoseService: NSObject, NSWindowDelegate {
    private let logger = Logger(
        subsystem: "com.huyee.chiphand",
        category: "mediapipe-web"
    )
    var onPose: ((HandPose?) -> Void)?
    var onReady: ((String) -> Void)?
    var onPerformance: ((Int, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onPreviewClosed: (() -> Void)?

    private var webView: WKWebView?
    private var panel: NSPanel?
    private var server: LocalMediaServer?
    private var previewVisible = false
    private var controlHand: Handedness = .right
    private var pointerModeEnabled = false

    func start() {
        stop()
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("MediaPipeRecognizer"),
              FileManager.default.fileExists(atPath: root.path),
              FileManager.default.fileExists(
                atPath: root.appendingPathComponent("native-recognizer.html").path
              ) else {
            onError?("MediaPipe 运行资源缺失")
            return
        }

        let controller = WKUserContentController()
        controller.add(self, name: "handPose")
        controller.addUserScript(WKUserScript(
            source: """
            (() => {
              const report = (value) => {
                const message = value instanceof Error
                  ? `${value.name}: ${value.message}`
                  : String(value ?? "未知 JavaScript 错误");
                window.webkit?.messageHandlers?.handPose?.postMessage({
                  type: "error",
                  message: `WebKit: ${message}`
                });
              };
              window.addEventListener("error", (event) => report(event.error ?? event.message));
              window.addEventListener("unhandledrejection", (event) => report(event.reason));
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 420),
            configuration: configuration
        )
        webView.uiDelegate = self
        webView.navigationDelegate = self

        // Keep a tiny non-activating surface alive. A completely detached or
        // hidden WKWebView is aggressively throttled and cannot sustain 30 FPS.
        let panel = NSPanel(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 560, height: 420),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "MediaPipe 手势校准"
        panel.delegate = self
        panel.contentView = webView
        panel.alphaValue = 0.01
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.orderFrontRegardless()

        self.webView = webView
        self.panel = panel
        setPreviewVisible(previewVisible)
        let server = LocalMediaServer(root: root)
        self.server = server
        server.start { [weak self, weak server] result in
            guard let self, let server, self.server === server else { return }
            switch result {
            case let .success(baseURL):
                webView.load(URLRequest(url: baseURL.appendingPathComponent("native-recognizer.html")))
            case let .failure(error):
                self.onError?("MediaPipe 本机服务失败：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        webView?.evaluateJavaScript("window.stopRecognition?.()")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "handPose")
        webView?.stopLoading()
        server?.stop()
        panel?.orderOut(nil)
        webView = nil
        server = nil
        panel = nil
    }

    func setPreviewVisible(_ visible: Bool) {
        previewVisible = visible
        guard let panel else { return }
        panel.ignoresMouseEvents = !visible
        if visible {
            panel.alphaValue = 1
            panel.center()
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0.01
            panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            panel.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        previewVisible = false
        onPreviewClosed?()
    }

    func setControlHand(_ hand: Handedness) {
        controlHand = hand
        let rawValue = hand == .right ? "Right" : "Left"
        webView?.evaluateJavaScript("window.setControlHand?.('\(rawValue)')")
    }

    func setPointerModeEnabled(_ enabled: Bool) {
        pointerModeEnabled = enabled
        webView?.evaluateJavaScript("window.setPointerModeEnabled?.(\(enabled ? "true" : "false"))")
    }

    private func decodePose(_ body: [String: Any]) -> HandPose? {
        guard let rawLandmarks = body["landmarks"] as? [[String: Any]],
              rawLandmarks.count >= 21 else { return nil }
        let joints: [HandJoint] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip,
        ]
        var points: [HandJoint: NormalizedPoint] = [:]
        for (index, joint) in joints.enumerated() {
            let raw = rawLandmarks[index]
            guard let x = raw["x"] as? Double,
                  let y = raw["y"] as? Double else { continue }
            points[joint] = NormalizedPoint(x: x, y: 1 - y, confidence: 1)
        }
        guard points.count == 21 else { return nil }
        let handedness: Handedness?
        switch body["handedness"] as? String {
        case "Left": handedness = .left
        case "Right": handedness = .right
        default: handedness = nil
        }
        let recognizedGesture = RecognizedGesture(
            rawValue: body["gesture"] as? String ?? "None"
        ) ?? .unknown
        return HandPose(
            points: points,
            confidence: body["confidence"] as? Double ?? 0,
            handedness: handedness,
            recognizedGesture: recognizedGesture,
            gestureConfidence: body["gestureConfidence"] as? Double ?? 0,
            inferenceDuration: (body["inferenceDuration"] as? Double ?? 0) / 1_000
        )
    }
}

extension MediaPipeHandPoseService: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {
            case "progress":
                self.logger.info(
                    "progress: \(body["message"] as? String ?? "unknown", privacy: .public)"
                )
            case "ready":
                self.setControlHand(self.controlHand)
                self.setPointerModeEnabled(self.pointerModeEnabled)
                self.onReady?("MediaPipe \(body["delegate"] as? String ?? "")")
            case "pose":
                self.onPerformance?(
                    body["recognitionFPS"] as? Int ?? 0,
                    body["inferenceDuration"] as? Double ?? 0
                )
                self.onPose?(self.decodePose(body))
            case "lost":
                self.onPose?(nil)
            case "error":
                self.onError?(body["message"] as? String ?? "MediaPipe 未知错误")
            default:
                break
            }
        }
    }
}

extension MediaPipeHandPoseService: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .camera ? .grant : .deny)
    }
}

extension MediaPipeHandPoseService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        logger.info("page loaded: \(webView.url?.absoluteString ?? "unknown", privacy: .public)")
        setControlHand(controlHand)
        setPointerModeEnabled(pointerModeEnabled)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        onError?("MediaPipe 页面失败：\(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        onError?("MediaPipe 资源失败：\(error.localizedDescription)")
    }
}
