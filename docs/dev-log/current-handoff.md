# 当前交接

## 当前阶段

- 第 04 阶段：macOS 系统级手势控制原型。
- 浏览器插件冻结在本地 `v1.0.1`；macOS 当前版本 `0.4.0`，`macos-v0.3.0` 为 ⭐ 重要稳定版。
- 当前分支：`codex/macos-system-prototype`。

## 已完成

- 主识别引擎升级为 MediaPipe Gesture Recognizer 0.10.35：单手、完整 21 点、左右手、`Victory`/`Thumb_Up` 等内置姿态、GPU 优先/CPU 备用；Apple Vision 仅作启动失败兜底。
- MediaPipe HTML、WASM 和模型全部打包在 App 内，由进程内 `127.0.0.1` 随机端口提供给 WKWebView；摄像头画面和关键点不保存、不上传。
- 校准视频、骨架和全屏 HUD 统一为自拍镜像；显示层使用腕点和每指 3 段，底层仍保留 21 点用于姿态与捏合判断。
- 支持左右手颜色、张掌/握拳/单指/捏合/翻页动态状态；真实捏合时显示拇指食指中点圆，松开即消失。
- 捏合改为严格 OK 手势：拇指食指接触且中指、无名指、小指张开；握拳和两指偶然靠近不会启动滚动。
- 新增 V 手势稳定后向左挥返回，仅允许 Chrome、Safari、Edge、夸克；新增竖拇指点赞识别与标记，但不执行真实点赞。
- 识别窗口显示实时 FPS 与推理耗时，30 FPS 性能不足时自动降到 24 FPS。
- 全屏 HUD 点击穿透；状态条高于 Dock 36px 且离屏幕底部至少 120px，摄像头校准窗口可选显示。
- 系统滚动改为 `.cghidEventTap` 全局注入，事件位置设为目标前台窗口中心，修复 Chromium 可能忽略 `postToPid` 滚轮事件的问题。
- App 改为正常 Dock 控制窗口并保留菜单栏入口，解决菜单栏项目被隐藏后启动即退出、退出后找不到入口的问题。
- 已安装 `/Applications/GestureControl.app`；诊断实测 MediaPipe GPU ready，并实时返回“左手 · 已识别手掌姿态”。

## 已验证

- `npm test`：32 项全部通过。
- `npm run typecheck`：通过。
- `swift test`：12 项 XCTest 全部通过，包括严格 OK、握拳防误触、静止 V、V 左挥、冷却重激活和点赞稳定状态。
- `swift run GestureControlCoreChecks`：10 项全部通过。
- `swift build --target GestureControlApp`：通过。
- Release `.app`、Info.plist、camera entitlement、ad-hoc codesign：通过。
- v0.4.0 Gesture Recognizer 已在打包 App 中达到 MediaPipe GPU ready，摄像头、模型和 WKWebView 本机服务链路正常。
- 最终 `0.4.0`（build 5）已安装并启动于 `/Applications/GestureControl.app`，ad-hoc 签名和内置手势模型校验通过。

## 尚未验证

- 最终 ad-hoc v0.4.0 替换后，若旧辅助功能授权失效，需要只对最终 `/Applications/GestureControl.app` 重新授权一次。
- 尚需用户实测四个浏览器的 V 左挥返回、严格 OK 捏合、点赞状态和底部状态条位置。
- 60 秒真实手掌下的平均推理耗时、有效 FPS 与两分钟静止误触率尚未记录。
- 当前没有 Developer ID 正式签名、notarization 或自动更新。

## 下一步

1. 启动 `/Applications/GestureControl.app`；只有实际显示辅助功能未允许时才重新授权。
2. 在 Chrome、Safari、Edge、夸克分别保持 V 手势 220ms 后向左挥，确认只返回一次；静止 V 不返回。
3. 验证握拳不滚动，只有标准 OK 手势捏住并上下移动才滚动。
4. 验证竖拇指只显示“点赞手势已识别（测试模式）”和绿色标记，不改变网页点赞。
5. 检查状态条位于 Dock 上方，并记录 60 秒 FPS/推理耗时和两分钟误触率。

## 重要边界

- 不加入鼠标移动、点击或 Air Mouse，除非当前滚动原型验收通过且用户明确进入下一阶段。
- 不申请屏幕录制或输入监控权限。
- 不推送 GitHub、申请证书、notarize 或发布 App Store，除非用户明确要求。
- 浏览器插件回滚点为本地 tag `v1.0.1`；macOS 重要稳定回滚点为 `macos-v0.3.0`。
