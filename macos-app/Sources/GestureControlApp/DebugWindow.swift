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
                HandSkeletonView(
                    pose: model.latestPose,
                    isPinching: model.isPinching,
                    coordinateMode: .cameraAspectFill,
                    mirrored: true
                )
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
    enum CoordinateMode {
        case stretch
        case cameraAspectFill
    }

    let pose: HandPose?
    var isPinching = false
    var coordinateMode: CoordinateMode = .stretch
    var mirrored = false
    var lineWidth: CGFloat = 2.5
    var pointDiameter: CGFloat = 8

    private let connections: [(HandJoint, HandJoint)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleTip),
        (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP),
    ]

    private let visibleJoints: [HandJoint] = [
        .wrist,
        .thumbCMC, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexTip,
        .middleMCP, .middlePIP, .middleTip,
        .ringMCP, .ringPIP, .ringTip,
        .littleMCP, .littlePIP, .littleTip,
    ]

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let handColor: Color = switch pose.handedness {
            case .left: .red
            case .right: .blue
            case nil: .cyan
            }
            for (from, to) in connections {
                guard let first = pose.point(from), let second = pose.point(to) else { continue }
                var path = Path()
                path.move(to: screenPoint(first, size: size))
                path.addLine(to: screenPoint(second, size: size))
                context.stroke(path, with: .color(handColor.opacity(0.9)), lineWidth: lineWidth)
            }

            if isPinching,
               let thumb = pose.point(.thumbTip),
               let index = pose.point(.indexTip),
               let center = pinchCenter(pose) {
                var pinchPath = Path()
                pinchPath.move(to: screenPoint(thumb, size: size))
                pinchPath.addLine(to: screenPoint(index, size: size))
                context.stroke(
                    pinchPath,
                    with: .color(.yellow.opacity(0.95)),
                    style: StrokeStyle(lineWidth: lineWidth * 2, lineCap: .round)
                )
                let pinchPoint = screenPoint(center, size: size)
                let diameter = max(18, pointDiameter * 2.4)
                let pinchRect = CGRect(
                    x: pinchPoint.x - diameter / 2,
                    y: pinchPoint.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: pinchRect), with: .color(.yellow))
                context.stroke(Path(ellipseIn: pinchRect), with: .color(.white), lineWidth: 2)
            }

            for joint in visibleJoints {
                guard let point = pose.point(joint) else { continue }
                let center = screenPoint(point, size: size)
                let radius = pointDiameter / 2
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: pointDiameter,
                    height: pointDiameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(handColor),
                    lineWidth: max(1.5, lineWidth * 0.6)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func screenPoint(_ point: NormalizedPoint, size: CGSize) -> CGPoint {
        let normalizedY = 1 - point.y
        let normalizedX = mirrored ? 1 - point.x : point.x
        switch coordinateMode {
        case .stretch:
            return CGPoint(x: normalizedX * size.width, y: normalizedY * size.height)
        case .cameraAspectFill:
            let cameraAspect: CGFloat = 4 / 3
            let targetAspect = size.width / max(size.height, 1)
            if targetAspect > cameraAspect {
                let scaledHeight = size.width / cameraAspect
                let offsetY = (size.height - scaledHeight) / 2
                return CGPoint(x: normalizedX * size.width, y: offsetY + normalizedY * scaledHeight)
            }
            let scaledWidth = size.height * cameraAspect
            let offsetX = (size.width - scaledWidth) / 2
            return CGPoint(x: offsetX + normalizedX * scaledWidth, y: normalizedY * size.height)
        }
    }
}
