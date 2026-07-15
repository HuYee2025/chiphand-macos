import AppKit
import GestureControlCore
import SwiftUI

private enum FeedbackDockSide: String {
    case left
    case right
}

@MainActor
private final class FeedbackPanelState: ObservableObject {
    @Published var isCollapsed: Bool
    @Published var dockSide: FeedbackDockSide?

    init(isCollapsed: Bool, dockSide: FeedbackDockSide?) {
        self.isCollapsed = isCollapsed
        self.dockSide = dockSide
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
        static let dockSide = "feedbackPanelDockSide"
        static let xFraction = "feedbackPanelXFraction"
        static let yFraction = "feedbackPanelYFraction"
    }

    private let expandedSize = CGSize(width: 390, height: 52)
    private let collapsedSize = CGSize(width: 30, height: 52)
    private let snapDistance: CGFloat = 72
    private weak var model: AppModel?
    private var skeletonPanel: NSPanel?
    private var feedbackPanel: PassiveFeedbackPanel?
    private var dragStartOrigin: CGPoint?
    private var screenObserver: NSObjectProtocol?
    private let feedbackState: FeedbackPanelState

    init(model: AppModel) {
        self.model = model
        let defaults = UserDefaults.standard
        let dockSide = defaults.string(forKey: PreferenceKey.dockSide)
            .flatMap(FeedbackDockSide.init(rawValue:))
        feedbackState = FeedbackPanelState(
            isCollapsed: dockSide != nil && defaults.bool(forKey: PreferenceKey.collapsed),
            dockSide: dockSide
        )
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
        guard let model, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        makeSkeletonPanelIfNeeded(model: model, screen: screen)
        makeFeedbackPanelIfNeeded(model: model)

        skeletonPanel?.setFrame(screen.frame, display: true)
        if let feedbackPanel, !feedbackPanel.isVisible {
            feedbackPanel.setFrame(restoredFeedbackFrame(on: screen), display: true)
        }
        skeletonPanel?.orderFrontRegardless()
        feedbackPanel?.orderFrontRegardless()
    }

    func hide() {
        skeletonPanel?.orderOut(nil)
        feedbackPanel?.orderOut(nil)
        dragStartOrigin = nil
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
                onDragChanged: { [weak self] translation in
                    self?.dragFeedbackPanel(by: translation)
                },
                onDragEnded: { [weak self] translation in
                    self?.finishDraggingFeedbackPanel(by: translation)
                },
                onTap: { [weak self] in
                    self?.expandFeedbackPanel()
                }
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

    private func dragFeedbackPanel(by translation: CGSize) {
        guard let panel = feedbackPanel,
              let screen = screen(containing: panel.frame) else { return }

        if feedbackState.isCollapsed {
            dragCollapsedPanel(panel, on: screen, by: translation)
            return
        }

        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let dragStartOrigin else { return }
        let proposedOrigin = CGPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        )
        panel.setFrameOrigin(clampedOrigin(proposedOrigin, size: panel.frame.size, on: screen))
    }

    private func dragCollapsedPanel(
        _ panel: NSPanel,
        on screen: NSScreen,
        by translation: CGSize
    ) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let dragStartOrigin else { return }
        let proposedOrigin = CGPoint(
            x: dragStartOrigin.x,
            y: dragStartOrigin.y - translation.height
        )
        panel.setFrameOrigin(clampedOrigin(proposedOrigin, size: panel.frame.size, on: screen))
    }

    private func finishDraggingFeedbackPanel(by translation: CGSize) {
        guard let panel = feedbackPanel,
              let screen = screen(containing: panel.frame) else {
            dragStartOrigin = nil
            return
        }
        defer { dragStartOrigin = nil }

        if feedbackState.isCollapsed {
            let shouldExpand = switch feedbackState.dockSide {
            case .left: translation.width > 18
            case .right: translation.width < -18
            case nil: false
            }
            if shouldExpand {
                expandFeedbackPanel()
            } else {
                snapCollapsedPanel(panel, to: feedbackState.dockSide ?? .right, on: screen)
                saveFeedbackPosition(panel.frame, on: screen)
            }
            return
        }

        if panel.frame.minX <= screen.frame.minX + snapDistance {
            collapseFeedbackPanel(to: .left, on: screen)
        } else if panel.frame.maxX >= screen.frame.maxX - snapDistance {
            collapseFeedbackPanel(to: .right, on: screen)
        } else {
            feedbackState.dockSide = nil
            saveFeedbackPosition(panel.frame, on: screen)
        }
    }

    private func collapseFeedbackPanel(to side: FeedbackDockSide, on screen: NSScreen) {
        guard let panel = feedbackPanel else { return }
        feedbackState.dockSide = side
        feedbackState.isCollapsed = true
        panel.hasShadow = false
        var frame = panel.frame
        frame.size = collapsedSize
        panel.setFrame(frame, display: true, animate: true)
        snapCollapsedPanel(panel, to: side, on: screen)
        saveFeedbackPosition(panel.frame, on: screen)
    }

    private func expandFeedbackPanel() {
        guard feedbackState.isCollapsed,
              let panel = feedbackPanel,
              let screen = screen(containing: panel.frame),
              let side = feedbackState.dockSide else { return }
        feedbackState.isCollapsed = false
        panel.hasShadow = true
        var frame = panel.frame
        frame.size = expandedSize
        frame.origin.x = side == .left
            ? screen.frame.minX + 12
            : screen.frame.maxX - expandedSize.width - 12
        frame.origin = clampedOrigin(frame.origin, size: frame.size, on: screen)
        panel.setFrame(frame, display: true, animate: true)
        saveFeedbackPosition(panel.frame, on: screen)
    }

    private func snapCollapsedPanel(
        _ panel: NSPanel,
        to side: FeedbackDockSide,
        on screen: NSScreen
    ) {
        var origin = panel.frame.origin
        origin.x = side == .left
            ? screen.frame.minX
            : screen.frame.maxX - collapsedSize.width
        panel.setFrameOrigin(clampedOrigin(origin, size: collapsedSize, on: screen))
    }

    private func restoredFeedbackFrame(on screen: NSScreen) -> CGRect {
        let defaults = UserDefaults.standard
        let size = feedbackState.isCollapsed ? collapsedSize : expandedSize
        let visible = screen.visibleFrame
        let horizontalBounds = screen.frame
        let availableX = max(0, horizontalBounds.width - size.width)
        let availableY = max(0, visible.height - size.height)
        let storedX = defaults.object(forKey: PreferenceKey.xFraction) as? Double
        let storedY = defaults.object(forKey: PreferenceKey.yFraction) as? Double
        var origin = CGPoint(
            x: storedX.map { horizontalBounds.minX + availableX * CGFloat($0) }
                ?? horizontalBounds.midX - size.width / 2,
            y: storedY.map { visible.minY + availableY * CGFloat($0) }
                ?? max(visible.minY + 24, screen.frame.minY + 120)
        )
        origin = clampedOrigin(origin, size: size, on: screen)

        if feedbackState.isCollapsed, let side = feedbackState.dockSide {
            origin.x = side == .left
                ? screen.frame.minX
                : screen.frame.maxX - size.width
        }
        return CGRect(origin: origin, size: size)
    }

    private func saveFeedbackPosition(_ frame: CGRect, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let horizontalBounds = screen.frame
        let availableX = max(1, horizontalBounds.width - frame.width)
        let availableY = max(1, visible.height - frame.height)
        let xFraction = min(1, max(0, (frame.minX - horizontalBounds.minX) / availableX))
        let yFraction = min(1, max(0, (frame.minY - visible.minY) / availableY))
        let defaults = UserDefaults.standard
        defaults.set(xFraction, forKey: PreferenceKey.xFraction)
        defaults.set(yFraction, forKey: PreferenceKey.yFraction)
        defaults.set(feedbackState.isCollapsed, forKey: PreferenceKey.collapsed)
        defaults.set(feedbackState.dockSide?.rawValue, forKey: PreferenceKey.dockSide)
    }

    private func repositionForCurrentScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        skeletonPanel?.setFrame(screen.frame, display: true)
        feedbackPanel?.setFrame(restoredFeedbackFrame(on: screen), display: true)
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func clampedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        on screen: NSScreen
    ) -> CGPoint {
        let visible = screen.visibleFrame
        let horizontalBounds = screen.frame
        return CGPoint(
            x: min(
                max(origin.x, horizontalBounds.minX),
                max(horizontalBounds.minX, horizontalBounds.maxX - size.width)
            ),
            y: min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
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
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let onTap: () -> Void

    var body: some View {
        Group {
            if state.isCollapsed {
                collapsedTab
            } else {
                expandedCapsule
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { onDragChanged($0.translation) }
                .onEnded { onDragEnded($0.translation) }
        )
        .onTapGesture(perform: onTap)
        .accessibilityLabel(state.isCollapsed ? "展开手势反馈" : model.handStatus)
        .help(state.isCollapsed ? "点击展开；向屏幕内拖动也可展开" : "拖到屏幕左侧或右侧可吸附隐藏")
    }

    private var expandedCapsule: some View {
        HStack(spacing: 10) {
            statusDot
            Text(model.handStatus)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 17)
        .frame(height: 44)
        .background(.black.opacity(0.76), in: Capsule())
        .padding(4)
    }

    private var collapsedTab: some View {
        statusDot
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 15))
            .padding(.vertical, 4)
    }

    private var statusDot: some View {
        Circle()
            .fill(model.latestPose == nil ? Color.orange : Color.green)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
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
