# 第 05 阶段检查点：薯片手 v1 开源候选版

日期：2026-07-16

## 阶段结果

- 产品正式命名为“薯片手 / ChipHand”，当前版本为 macOS `1.0.1 build 22`。
- 当前分支为 `codex/macos-system-prototype`；本地标签 `macos-v1.0.1`，`macos-v1.0.0` 为候选版回滚点。
- App 已改为自包含 Universal 应用，覆盖 `arm64 + x86_64`，普通用户不需要安装 Xcode、Node.js、Python 或浏览器插件。
- 已生成 DMG、ZIP、SHA-256、离线使用说明、正式图标、手势插图和开源许可；暂未上传 GitHub。

## 当前核心交互

- 张开手掌左右挥动：上翻/下翻页面。
- 严格 OK 捏合上下移动：连续滚动。
- 严格 OK 从左右两侧跨中线：浏览器返回/前进；跨线时显示白线蓝光确认。
- 竖起食指：黄色控制点跟随真实鼠标；定位后拇指与中指轻捏执行单击。
- 食指控制点和指针功能永久开启，不再提供“显示控制点”开关。
- 右手/左手只能选择一只作为控制手。
- 反馈条支持右侧收起、上下移动、双击恢复，以及双击暂停/继续识别。

## 关键技术与边界

- 主识别引擎：MediaPipe Gesture Recognizer，单手 21 点；Apple Vision 仅作备用。
- 系统事件通过 Core Graphics 发送；返回/前进和食指指针仅允许 Chrome、Safari、Edge、夸克。
- 固定 bundle ID：`com.huyee.chiphand`。
- 免费开源版采用 ad-hoc 签名，不购买 Developer ID，也不 notarize；其他用户首次下载需要右键“打开”或在隐私与安全性中放行。
- 识别、视频帧、WASM 和模型全部在本机运行，不上传摄像头画面。

## 验证结果

- `swift test`：33 项通过。
- `swift run GestureControlCoreChecks`：22 项通过。
- `npm test`：32 项通过；`npm run typecheck` 通过。
- warnings-as-errors Universal Release 构建、codesign、DMG 挂载、SHA-256 和安装版 UI 检查均通过。
- 本机已安装 `/Applications/薯片手.app`，版本为 `1.0.1 build 22`。

## 本地产物

- `macos-app/releases/ChipHand-macOS-1.0.1-universal.dmg`
- `macos-app/releases/ChipHand-macOS-1.0.1-universal.zip`
- `macos-app/releases/SHA256SUMS.txt`
- `docs/user-guide/index.html`

## 下一对话任务

- 继续用户实机测试和细节优化，不改变已验证的食指跟踪手感、严格 OK 规则和现有回滚点。
- 每次改动先判断是 patch 还是 minor 版本，再更新 `VERSION`、`Info.plist`、CHANGELOG、版本记录、构建产物和本地 tag。
- 用户确认本地候选版稳定之前，不上传 GitHub。

