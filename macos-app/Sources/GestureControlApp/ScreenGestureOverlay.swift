import AppKit
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

    var body: some View {
        ZStack {
            Color.clear
            HandSkeletonView(
                pose: model.latestPose,
                lineWidth: 4,
                pointDiameter: 12
            )

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
                .padding(.bottom, 34)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
