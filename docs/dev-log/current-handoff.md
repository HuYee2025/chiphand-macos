# 当前交接

## 当前阶段

- 第 04 阶段：macOS 系统级手势控制原型。
- 浏览器插件冻结在本地 `v1.0.1`；不要继续多页面重构，除非用户重新改变方向。
- macOS 原型版本：`macos-app/VERSION` = `0.2.0`。
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
- `0.1.1` 修复辅助功能已打开却反复跳设置：启动不再自动跳转，权限每秒刷新，生效后自动继续。
- `0.1.1` 新增默认开启的置顶测试窗，显示摄像头、手部骨架、捏合连线和识别状态。
- App 已固定安装到 `/Applications/GestureControl.app`；旧辅助功能记录已重置。
- `0.2.0` 使用完整 21 点骨架，修复视频/骨架错位，并用结构校验过滤脸部假点云。
- `0.2.0` 修复置信度计算导致“看得见手、动作不执行”的问题。
- `0.2.0` 新增全屏透明 HUD、动态手势状态和“测试系统下翻”；摄像头窗口默认改为关闭。

## 已验证

- `swift test`：7 项 `XCTest` 全部通过。
- `swift run GestureControlCoreChecks`：10 项全部通过。
- `swift build --target GestureControlApp`：通过。
- Release `.app` 构建、Info.plist、camera entitlement、ad-hoc codesign：通过。
- `GestureControl.app` 进程可成功启动。
- `/Applications/GestureControl.app` 已更新为 `0.2.0`，签名校验通过并成功启动。
- Xcode 26.6 License 已接受；已建立标准 `XCTest` Target。

## 尚未验证

- 安装最终 `0.2.0` 后已重置旧记录，用户需要再授予一次辅助功能权限。
- 尚未用真实手掌确认 Vision 阈值、左右方向和 Core Graphics 滚动符号。
- 尚未在 Chrome、Safari、Preview、Notion 做跨应用成功率和误触测试。
- 悬浮识别窗已实现但尚待用户授权后做真实摄像头与骨架验收。
- 当前仍为本机 ad-hoc 签名，没有 Developer ID 正式签名证书。

## 下一步

1. 点击菜单栏手掌图标和“开启手势控制”；若辅助功能未生效，点权限行“设置”并重新打开 GestureControl 开关。
2. 先在长网页点击“测试系统下翻”；成功后说明权限和系统输出链路正常。
3. 确认全屏 21 点骨架随手移动，手离开时立即消失；必要时打开摄像头校准窗口检查对齐。
4. 验证动态状态、右挥下翻、左挥上翻、捏住手向上拖查看下方内容。
5. 完成 Chrome、Safari、Preview、Notion 各 20 次动作和两分钟静止误触记录，再调整 Vision 阈值与滚动增益。

## 重要边界

- 不要加入鼠标移动、点击或 Air Mouse，除非当前滚动原型验收通过且用户明确进入下一阶段。
- 不要申请屏幕录制或输入监控权限。
- 不要推送 GitHub、申请证书、notarize 或发布 App Store，除非用户明确要求。
- 浏览器插件回滚点为本地 tag `v1.0.1`；远端 GitHub 仍只有 `v0.1.0`。
