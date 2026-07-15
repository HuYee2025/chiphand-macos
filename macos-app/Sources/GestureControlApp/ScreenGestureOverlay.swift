import AppKit
import GestureControlCore
import SwiftUI

@MainActor
final class ScreenGestureOverlayController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if panel == nil {
            let bottomInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
            let hosting = NSHostingController(
                rootView: ScreenGestureOverlayView(model: model, bottomInset: bottomInset)
            )
            hosting.view.wantsLayer = true
            hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            self.panel = panel
        }
        panel?.setFrame(screen.frame, display: true)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct ScreenGestureOverlayView: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat

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

            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Circle()
                        .fill(model.latestPose == nil ? Color.orange : Color.green)
                        .frame(width: 10, height: 10)
                    Text(model.handStatus)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(.bottom, max(bottomInset + 36, 120))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
