import AppKit
import GestureControlCore
import SwiftUI

@MainActor
final class DebugWindowController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }
        if panel == nil {
            let content = DebugWindowView(model: model)
            let hosting = NSHostingController(rootView: content)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 390, height: 350),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "手势识别测试"
            panel.contentViewController = hosting
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.center()
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct DebugWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                CameraPreviewView(session: model.camera.session)
                HandSkeletonView(pose: model.latestPose)
                if model.latestPose == nil {
                    Text("请把一只手完整放入画面")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.62), in: Capsule())
                }
            }
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18)))

            HStack(spacing: 8) {
                Circle()
                    .fill(model.latestPose == nil ? Color.orange : Color.green)
                    .frame(width: 9, height: 9)
                Text(model.handStatus)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 390, height: 350)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HandSkeletonView: View {
    let pose: HandPose?

    private let connections: [(HandJoint, HandJoint)] = [
        (.wrist, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littleTip),
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP),
    ]

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            for (from, to) in connections {
                guard let first = pose.point(from), let second = pose.point(to) else { continue }
                var path = Path()
                path.move(to: screenPoint(first, size: size))
                path.addLine(to: screenPoint(second, size: size))
                context.stroke(path, with: .color(.cyan.opacity(0.9)), lineWidth: 2.5)
            }

            if let thumb = pose.point(.thumbTip), let index = pose.point(.indexTip) {
                var pinchPath = Path()
                pinchPath.move(to: screenPoint(thumb, size: size))
                pinchPath.addLine(to: screenPoint(index, size: size))
                let pinching = pinchStrength(pose) <= 0.20
                context.stroke(
                    pinchPath,
                    with: .color(pinching ? .green : .yellow.opacity(0.8)),
                    style: StrokeStyle(lineWidth: pinching ? 5 : 2, lineCap: .round)
                )
            }

            for point in pose.points.values {
                let center = screenPoint(point, size: size)
                let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(Path(ellipseIn: rect), with: .color(.cyan), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func screenPoint(_ point: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (1 - point.x) * size.width, y: (1 - point.y) * size.height)
    }
}
