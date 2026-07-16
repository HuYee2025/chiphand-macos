import AppKit
import GestureControlCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    private let brandBlue = Color(red: 0.0, green: 0.184, blue: 0.655)
    private let chipYellow = Color(red: 1.0, green: 0.76, blue: 0.12)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                brandHeader
                statusCard

                Button(primaryButtonTitle) {
                    model.toggle()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(brandBlue)
                .frame(maxWidth: .infinity)

                permissionCard
                sensitivityCard
                operationCard
                displayCard
                footer
            }
            .padding(16)
        }
        .frame(width: 348)
        .frame(minHeight: 600, maxHeight: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshPermissions() }
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("薯片手")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("ChipHand")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(brandBlue)
                }
                Text("边吃薯片，边畅快浏览。")
                    .font(.callout.weight(.medium))
                Text("手不用碰键盘和触控板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.status)
                    .font(.subheadline.weight(.semibold))
                Text(model.handStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text(model.recognitionEngine)
                    if model.isRunning, model.inferenceDurationMS > 0 {
                        Text("·")
                        Text(String(format: "%.1f ms", model.inferenceDurationMS))
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brandBlue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(brandBlue.opacity(0.16), lineWidth: 1)
        )
    }

    private var permissionCard: some View {
        sectionCard("首次使用", icon: "checkmark.shield") {
            VStack(spacing: 9) {
                permissionRow("1", title: "摄像头", state: model.cameraPermission.rawValue) {
                    model.openCameraSettings()
                }
                permissionRow("2", title: "辅助功能", state: model.accessibilityPermission.rawValue) {
                    model.openAccessibilitySettings()
                }
                Text("两项权限只需在第一次使用时开启。识别在本机完成，画面不会上传。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sensitivityCard: some View {
        sectionCard("灵敏度", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                slider("左右挥手", value: $model.swipeSensitivity)
                slider("手指捏合", value: $model.pinchSensitivity)
            }
        }
    }

    private var operationCard: some View {
        sectionCard("手势速查", icon: "hand.raised") {
            VStack(alignment: .leading, spacing: 7) {
                gestureRow("张掌左右挥", detail: "翻页")
                gestureRow("OK 捏合上下移动", detail: "滚动")
                gestureRow("OK 捏合左右跨中线", detail: "返回 / 前进")
                gestureRow("食指定位 + 拇指中指轻捏", detail: "悬停 / 点击")
                gestureRow("竖起拇指", detail: "识别点赞，不执行")

                HStack {
                    Button("测试系统下翻") { model.testPageDown() }
                        .controlSize(.small)
                    Spacer()
                    Button("查看完整图解") { model.openUserGuide() }
                        .controlSize(.small)
                        .buttonStyle(.link)
                }
                .padding(.top, 2)
            }
        }
    }

    private var displayCard: some View {
        sectionCard("显示与控制", icon: "display") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("全屏显示手掌骨架", isOn: $model.screenOverlayEnabled)
                    .tint(brandBlue)
                Toggle("显示摄像头校准窗口", isOn: $model.debugWindowEnabled)
                    .tint(brandBlue)

                HStack {
                    Text("控制手")
                    Spacer()
                    Picker("控制手", selection: $model.controlHand) {
                        Text("右手").tag(Handedness.right)
                        Text("左手").tag(Handedness.left)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                }
            }
            .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button("刷新权限") { model.refreshPermissions() }
            Button("使用说明") { model.openUserGuide() }
            Spacer()
            Text("v1.0.1")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }

    private var statusColor: Color {
        if model.isPaused { return .red }
        if model.isRunning { return .green }
        return .secondary.opacity(0.45)
    }

    private var primaryButtonTitle: String {
        if model.isPaused { return "恢复手势控制" }
        return model.isRunning ? "停止手势控制" : "开启手势控制"
    }

    private func sectionCard<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brandBlue)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func permissionRow(
        _ step: String,
        title: String,
        state: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            Text(step)
                .font(.caption2.bold())
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(chipYellow))
            Text(title)
            Spacer()
            Text(state)
                .font(.caption)
                .foregroundStyle(state == PermissionState.granted.rawValue ? .green : .secondary)
            if state != PermissionState.granted.rawValue {
                Button("设置", action: action)
                    .controlSize(.small)
            }
        }
    }

    private func gestureRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(chipYellow)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
            Spacer(minLength: 8)
            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...100, step: 1)
                .tint(brandBlue)
        }
        .font(.caption)
    }
}
