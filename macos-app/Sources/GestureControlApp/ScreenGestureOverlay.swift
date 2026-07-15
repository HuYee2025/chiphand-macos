import AppKit
import GestureControlCore
import SwiftUI

@MainActor
private final class FeedbackPanelState: ObservableObject {
    @Published var isCollapsed: Bool

    init(isCollapsed: Bool) {
        self.isCollapsed = isCollapsed
    }
}

private final class PassiveFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenGestureOverlayController {
    private enum PreferenceKey {
        static let collapsed = "feedbackPanelCollapsed"
        static let yFraction = "feedbackPanelYFraction"
        static let legacyDockSide = "feedbackPanelDockSide"
        static let legacyXFraction = "feedbackPanelXFraction"
    }

    private let expandedSize = CGSize(width: 390, height: 52)
    private let collapsedSize = CGSize(width: 30, height: 44)
    private weak var model: AppModel?
    private var skeletonPanel: NSPanel?
    private var feedbackPanel: PassiveFeedbackPanel?
    private var miniDragStart: (mouseY: CGFloat, panelY: CGFloat)?
    private var screenObserver: NSObjectProtocol?
    private let feedbackState: FeedbackPanelState

    init(model: AppModel) {
        self.model = model
        let defaults = UserDefaults.standard
        feedbackState = FeedbackPanelState(
            isCollapsed: defaults.bool(forKey: PreferenceKey.collapsed)
        )
        defaults.removeObject(forKey: PreferenceKey.legacyDockSide)
        defaults.removeObject(forKey: PreferenceKey.legacyXFraction)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionForCurrentScreen() }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        present(showSkeleton: true)
    }

    func showFeedbackOnly() {
        present(showSkeleton: false)
    }

    func hide() {
        skeletonPanel?.orderOut(nil)
        feedbackPanel?.orderOut(nil)
        miniDragStart = nil
    }

    private func present(showSkeleton: Bool) {
        guard let model, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        makeSkeletonPanelIfNeeded(model: model, screen: screen)
        makeFeedbackPanelIfNeeded(model: model)

        skeletonPanel?.setFrame(screen.frame, display: true)
        if showSkeleton {
            skeletonPanel?.orderFrontRegardless()
        } else {
            skeletonPanel?.orderOut(nil)
        }
        if let feedbackPanel, !feedbackPanel.isVisible {
            feedbackPanel.setFrame(restoredFeedbackFrame(on: screen), display: true)
        }
        feedbackPanel?.orderFrontRegardless()
    }

    private func makeSkeletonPanelIfNeeded(model: AppModel, screen: NSScreen) {
        guard skeletonPanel == nil else { return }
        let hosting = NSHostingController(rootView: ScreenGestureOverlayView(model: model))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        configureOverlayPanel(panel, acceptsMouse: false)
        panel.hasShadow = false
        skeletonPanel = panel
    }

    private func makeFeedbackPanelIfNeeded(model: AppModel) {
        guard feedbackPanel == nil else { return }
        let hosting = NSHostingController(
            rootView: FeedbackStatusView(
                model: model,
                state: feedbackState,
                onCollapse: { [weak self] in self?.collapseFeedbackPanel() },
                onTogglePause: { [weak model] in model?.togglePauseFromFeedback() },
                onMiniMouseDown: { [weak self] mouseY in self?.beginMiniDrag(mouseY: mouseY) },
                onMiniMouseDragged: { [weak self] mouseY in self?.dragMiniPanel(mouseY: mouseY) },
                onMiniMouseUp: { [weak self] in self?.finishMiniDrag() },
                onMiniDoubleClick: { [weak self] in self?.restoreDefaultFeedbackPanel() }
            )
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = PassiveFeedbackPanel(
            contentRect: CGRect(origin: .zero, size: expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        configureOverlayPanel(panel, acceptsMouse: true)
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        feedbackPanel = panel
    }

    private func configureOverlayPanel(_ panel: NSPanel, acceptsMouse: Bool) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = !acceptsMouse
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    private func collapseFeedbackPanel() {
        guard !feedbackState.isCollapsed,
              let panel = feedbackPanel,
              let screen = screen(containing: panel.frame) else { return }
        feedbackState.isCollapsed = true
        panel.hasShadow = false
        let defaultMiniY = panel.frame.midY - collapsedSize.height / 2
        panel.setFrame(
            collapsedFeedbackFrame(on: screen, fallbackY: defaultMiniY),
            display: true,
            animate: true
        )
        saveCollapsedPosition(panel.frame, on: screen)
    }

    private func restoreDefaultFeedbackPanel() {
        guard feedbackState.isCollapsed,
              let panel = feedbackPanel,
              let screen = screen(containing: panel.frame) else { return }
        miniDragStart = nil
        feedbackState.isCollapsed = false
        panel.hasShadow = true
        panel.setFrame(defaultFeedbackFrame(on: screen), display: true, animate: true)
        UserDefaults.standard.set(false, forKey: PreferenceKey.collapsed)
    }

    private func beginMiniDrag(mouseY: CGFloat) {
        guard feedbackState.isCollapsed, let panel = feedbackPanel else { return }
        miniDragStart = (mouseY: mouseY, panelY: panel.frame.minY)
    }

    private func dragMiniPanel(mouseY: CGFloat) {
        guard feedbackState.isCollapsed,
              let panel = feedbackPanel,
              let start = miniDragStart,
              let screen = screen(containing: panel.frame) else { return }
        let proposedY = start.panelY + mouseY - start.mouseY
        let visible = screen.visibleFrame
        let clampedY = min(
            max(proposedY, visible.minY),
            max(visible.minY, visible.maxY - collapsedSize.height)
        )
        panel.setFrameOrigin(CGPoint(
            x: screen.frame.maxX - collapsedSize.width,
            y: clampedY
        ))
    }

    private func finishMiniDrag() {
        guard feedbackState.isCollapsed,
              let panel = feedbackPanel,
              let screen = screen(containing: panel.frame) else {
            miniDragStart = nil
            return
        }
        miniDragStart = nil
        saveCollapsedPosition(panel.frame, on: screen)
    }

    private func restoredFeedbackFrame(on screen: NSScreen) -> CGRect {
        feedbackState.isCollapsed
            ? collapsedFeedbackFrame(on: screen, fallbackY: defaultFeedbackFrame(on: screen).minY)
            : defaultFeedbackFrame(on: screen)
    }

    private func defaultFeedbackFrame(on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: screen.frame.midX - expandedSize.width / 2,
            y: max(visible.minY + 24, screen.frame.minY + 120)
        )
        return CGRect(origin: origin, size: expandedSize)
    }

    private func collapsedFeedbackFrame(on screen: NSScreen, fallbackY: CGFloat) -> CGRect {
        let visible = screen.visibleFrame
        let availableY = max(0, visible.height - collapsedSize.height)
        let storedY = UserDefaults.standard.object(forKey: PreferenceKey.yFraction) as? Double
        let proposedY = storedY.map { visible.minY + availableY * CGFloat($0) } ?? fallbackY
        let y = min(
            max(proposedY, visible.minY),
            max(visible.minY, visible.maxY - collapsedSize.height)
        )
        return CGRect(
            origin: CGPoint(x: screen.frame.maxX - collapsedSize.width, y: y),
            size: collapsedSize
        )
    }

    private func saveCollapsedPosition(_ frame: CGRect, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let availableY = max(1, visible.height - collapsedSize.height)
        let yFraction = min(1, max(0, (frame.minY - visible.minY) / availableY))
        let defaults = UserDefaults.standard
        defaults.set(yFraction, forKey: PreferenceKey.yFraction)
        defaults.set(true, forKey: PreferenceKey.collapsed)
    }

    private func repositionForCurrentScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        skeletonPanel?.setFrame(screen.frame, display: true)
        if feedbackPanel?.isVisible == true {
            feedbackPanel?.setFrame(restoredFeedbackFrame(on: screen), display: true)
        }
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

private struct ScreenGestureOverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.clear
            HandSkeletonView(
                pose: model.latestPose,
                isPinching: model.isPinching,
                showPointingTip: model.showsPointingTip,
                mirrored: true,
                lineWidth: 4,
                pointDiameter: 12
            )
            if model.isThumbsUp {
                ThumbsUpBadgeView(pose: model.latestPose, mirrored: true)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct FeedbackStatusView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: FeedbackPanelState
    let onCollapse: () -> Void
    let onTogglePause: () -> Void
    let onMiniMouseDown: (CGFloat) -> Void
    let onMiniMouseDragged: (CGFloat) -> Void
    let onMiniMouseUp: () -> Void
    let onMiniDoubleClick: () -> Void

    var body: some View {
        Group {
            if state.isCollapsed {
                collapsedTab
            } else {
                expandedCapsule
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedCapsule: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                statusDot
                Text(model.handStatus)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onTogglePause)
            .accessibilityLabel(model.isPaused ? "恢复手势控制" : "暂停手势控制")
            .help(model.isPaused ? "双击恢复手势识别" : "双击暂停手势识别")

            Button(action: onCollapse) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.66))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起手势反馈")
            .help("收起到屏幕右侧")
        }
        .foregroundStyle(.white)
        .padding(.leading, 17)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(.black.opacity(0.76), in: Capsule())
        .padding(4)
    }

    private var collapsedTab: some View {
        ZStack {
            RightEdgeTabShape()
                .fill(.black.opacity(0.78))
            statusDot
            MiniPanelInteractionView(
                onMouseDown: onMiniMouseDown,
                onMouseDragged: onMiniMouseDragged,
                onMouseUp: onMiniMouseUp,
                onDoubleClick: onMiniDoubleClick
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("迷你手势反馈")
        .help("上下拖动调整高度；双击恢复默认位置")
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
    }

    private var statusColor: Color {
        if model.isPaused { return .red }
        return model.latestPose == nil ? .orange : .green
    }
}

private struct RightEdgeTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, rect.width)
        let kappa: CGFloat = 0.552_284_75
        var path = Path()
        path.move(to: CGPoint(x: radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: radius - kappa * radius, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.midY + kappa * radius)
        )
        path.addCurve(
            to: CGPoint(x: radius, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.midY - kappa * radius),
            control2: CGPoint(x: radius - kappa * radius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct MiniPanelInteractionView: NSViewRepresentable {
    let onMouseDown: (CGFloat) -> Void
    let onMouseDragged: (CGFloat) -> Void
    let onMouseUp: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> MiniPanelInteractionNSView {
        let view = MiniPanelInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: MiniPanelInteractionNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: MiniPanelInteractionNSView) {
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        view.onDoubleClick = onDoubleClick
    }
}

private final class MiniPanelInteractionNSView: NSView {
    var onMouseDown: ((CGFloat) -> Void)?
    var onMouseDragged: ((CGFloat) -> Void)?
    var onMouseUp: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let isDoubleClick = event.clickCount >= 2
        var didDrag = false
        onMouseDown?(screenY(for: event))
        guard let window else {
            onMouseUp?()
            return
        }
        while true {
            guard let nextEvent = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else {
                onMouseUp?()
                return
            }
            if nextEvent.type == .leftMouseUp {
                onMouseUp?()
                if isDoubleClick, !didDrag {
                    onDoubleClick?()
                }
                return
            }
            didDrag = true
            onMouseDragged?(screenY(for: nextEvent))
        }
    }

    private func screenY(for event: NSEvent) -> CGFloat {
        window?.convertPoint(toScreen: event.locationInWindow).y
            ?? NSEvent.mouseLocation.y
    }
}

struct ThumbsUpBadgeView: View {
    let pose: HandPose?
    var mirrored = false

    var body: some View {
        GeometryReader { geometry in
            if let pose, let palm = palmCenter(pose) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(.green.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .position(
                        x: (mirrored ? 1 - palm.x : palm.x) * geometry.size.width,
                        y: (1 - palm.y) * geometry.size.height
                    )
            }
        }
        .allowsHitTesting(false)
    }
}
