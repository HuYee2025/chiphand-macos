import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("系统手势控制")
                        .font(.headline)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(model.isRunning ? .green : .secondary)
                    Text("识别引擎：\(model.recognitionEngine)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
            }

            Text(model.handStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(model.isRunning ? "停止手势控制" : "开启手势控制") {
                model.toggle()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            GroupBox("权限") {
                VStack(spacing: 8) {
                    permissionRow("摄像头", state: model.cameraPermission.rawValue) {
                        model.openCameraSettings()
                    }
                    permissionRow("辅助功能", state: model.accessibilityPermission.rawValue) {
                        model.openAccessibilitySettings()
                    }
                }
                .padding(.vertical, 2)
            }

            GroupBox("灵敏度") {
                VStack(alignment: .leading, spacing: 10) {
                    slider("左右挥手", value: $model.swipeSensitivity)
                    slider("手指捏合", value: $model.pinchSensitivity)
                }
                .padding(.vertical, 2)
            }

            GroupBox("操作") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("张开手掌左右挥动：翻页")
                    Text("拇指食指捏住后上下移动：滚动")
                    Text("握拳、单指：只显示状态")
                    Button("测试系统下翻") { model.testPageDown() }
                        .controlSize(.small)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }

            Toggle("全屏显示手掌骨架", isOn: $model.screenOverlayEnabled)
            Toggle("显示摄像头校准窗口", isOn: $model.debugWindowEnabled)
            HStack {
                Button("刷新权限") { model.refreshPermissions() }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refreshPermissions() }
    }

    private func permissionRow(
        _ title: String,
        state: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
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
        }
    }
}
