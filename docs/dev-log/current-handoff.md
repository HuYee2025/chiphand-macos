# 当前交接

## 当前阶段

- 第 04 阶段：macOS 系统级手势控制原型。
- 浏览器插件冻结在本地 `v1.0.1`；macOS 当前版本 `0.3.0`。
- 当前分支：`codex/macos-system-prototype`。

## 已完成

- 主识别引擎切换为 MediaPipe Hand Landmarker 0.10.35：完整 21 点、左右手、最多双手检测、GPU 优先/CPU 备用；Apple Vision 仅作启动失败兜底。
- MediaPipe HTML、WASM 和模型全部打包在 App 内，由进程内 `127.0.0.1` 随机端口提供给 WKWebView；摄像头画面和关键点不保存、不上传。
- 校准视频、骨架和全屏 HUD 统一为自拍镜像；显示层使用腕点和每指 3 段，底层仍保留 21 点用于姿态与捏合判断。
- 支持左右手颜色、张掌/握拳/单指/捏合/翻页动态状态；真实捏合时显示拇指食指中点圆，松开即消失。
- 全屏 HUD 点击穿透，底部状态避开 Dock；摄像头校准窗口可选显示。
- 系统滚动改为 `.cghidEventTap` 全局注入，事件位置设为目标前台窗口中心，修复 Chromium 可能忽略 `postToPid` 滚轮事件的问题。
- App 改为正常 Dock 控制窗口并保留菜单栏入口，解决菜单栏项目被隐藏后启动即退出、退出后找不到入口的问题。
- 已安装 `/Applications/GestureControl.app`；诊断实测 MediaPipe GPU ready，并实时返回“左手 · 已识别手掌姿态”。

## 已验证

- `npm test`：32 项全部通过。
- `npm run typecheck`：通过。
- `swift test`：7 项 XCTest 全部通过。
- `swift run GestureControlCoreChecks`：10 项全部通过。
- `swift build --target GestureControlApp`：通过。
- Release `.app`、Info.plist、camera entitlement、ad-hoc codesign：通过。
- 最终 App 生命周期稳定，Dock 控制窗口、菜单栏入口、MediaPipe GPU、摄像头和实时手掌状态均已运行。

## 尚未验证

- 最终 ad-hoc 二进制替换后，辅助功能状态为“未允许”；用户需要对最终 `/Applications/GestureControl.app` 重新授权一次。
- 授权后尚需在 Chrome/X 实测“测试系统下翻”、右挥下翻、左挥上翻和捏合滚动。
- Safari、Preview、Notion 的跨应用成功率与两分钟静止误触率尚未记录。
- 当前没有 Developer ID 正式签名、notarization 或自动更新。

## 下一步

1. 在系统设置“隐私与安全性 → 辅助功能”里重新打开 GestureControl；若旧开关无效，删除旧项后用 `+` 选择 `/Applications/GestureControl.app`。
2. 回到 App，确认权限显示“已允许”，在 X 长页面点击“测试系统下翻”。
3. 成功后依次测试：右挥下翻、左挥上翻、捏住后手向上移动查看下方内容。
4. 检查镜像视频与骨架重合、侧手识别、左右手、捏合圆点和底部状态位置。
5. 记录 Chrome、Safari、Preview、Notion 各 20 次动作与两分钟误触，再调整阈值。

## 重要边界

- 不加入鼠标移动、点击或 Air Mouse，除非当前滚动原型验收通过且用户明确进入下一阶段。
- 不申请屏幕录制或输入监控权限。
- 不推送 GitHub、申请证书、notarize 或发布 App Store，除非用户明确要求。
- 浏览器插件回滚点为本地 tag `v1.0.1`；macOS 上一稳定回滚点为 `macos-v0.2.0`。
