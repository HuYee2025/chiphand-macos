# 当前交接

## 当前阶段

- 第 04 阶段：macOS 系统级手势控制原型。
- 浏览器插件冻结在本地 `v1.0.1`；不要继续多页面重构，除非用户重新改变方向。
- macOS 原型版本：`macos-app/VERSION` = `0.1.0`。
- 当前分支：`codex/macos-system-prototype`。

## 已完成

- 新增 SwiftUI 菜单栏 App，无 Dock 图标。
- AVFoundation 640×480 摄像头采集和可选镜像调试预览。
- Apple Vision 单手关键点检测，画面和关键点不保存、不上传。
- 左挥上翻、右挥下翻约 75% 屏幕；650ms 冷却并支持稳定手掌重新激活。
- 捏合稳定 80ms 后上下拖动连续滚动；松开、丢手、切换前台 App 立即停止。
- Core Graphics 滚动事件发送给前台 App PID；不移动光标，不发送点击或键盘事件。
- 摄像头/辅助功能权限状态与设置入口、两项灵敏度、本机持久化。
- `scripts/build-app.sh` 生成并 ad-hoc 签名 `build/GestureControl.app`。

## 已验证

- `swift run GestureControlCoreChecks`：10 项全部通过。
- `swift build --target GestureControlApp`：通过。
- Release `.app` 构建、Info.plist、camera entitlement、ad-hoc codesign：通过。
- `GestureControl.app` 进程可成功启动。
- 由于当前只有 Command Line Tools，尚未使用标准 Xcode 测试 Target。

## 尚未验证

- 用户尚未在系统弹窗/系统设置中授予摄像头和辅助功能权限。
- 尚未用真实手掌确认 Vision 阈值、左右方向和 Core Graphics 滚动符号。
- 尚未在 Chrome、Safari、Preview、Notion 做跨应用成功率和误触测试。
- 菜单栏 App 没有普通窗口，Computer Use 无法读取该状态项；UI 需用户实际点击菜单栏手掌图标验收。
- 完整 Xcode 尚未安装；本机 `xcode-select` 仍指向 Command Line Tools，也没有正式签名证书。

## 下一步

1. 用户从 App Store 安装完整 Xcode；首次启动完成组件安装并接受 License。
2. 重新运行 `./macos-app/scripts/build-app.sh`，打开 `macos-app/build/GestureControl.app`。
3. 点击菜单栏手掌图标，允许摄像头；按界面入口在系统设置中允许辅助功能，然后重新开启控制。
4. 先在长网页验证方向：右挥应下翻、左挥应上翻、捏住手向上移动应看到下方内容。
5. 完成 Chrome、Safari、Preview、Notion 各 20 次动作和两分钟静止误触记录，再调整 Vision 阈值与滚动增益。

## 重要边界

- 不要加入鼠标移动、点击或 Air Mouse，除非当前滚动原型验收通过且用户明确进入下一阶段。
- 不要申请屏幕录制或输入监控权限。
- 不要推送 GitHub、申请证书、notarize 或发布 App Store，除非用户明确要求。
- 浏览器插件回滚点为本地 tag `v1.0.1`；远端 GitHub 仍只有 `v0.1.0`。
