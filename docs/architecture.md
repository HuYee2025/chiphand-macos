# 薯片手架构说明

## 总览

薯片手把“摄像头画面 → 单手关键点 → 手势状态机 → macOS 系统事件”拆成独立层。识别层只描述手的位置与姿态，手势层决定用户意图，输出层才有权限操作前台应用。

```text
Mac 摄像头
  ↓
MediaPipe Gesture Recognizer（主引擎）
Apple Vision（启动失败时备用）
  ↓
21 点关键点、左右手、内置姿态、置信度
  ↓
GestureControlCore 状态机
  ↓
滚动 / 翻页 / 浏览器导航 / 鼠标移动与单击
  ↓
Core Graphics HID 事件 → 当前前台应用
```

## 识别层

`MediaPipeHandPoseService` 在 `WKWebView` 中运行打包在 App 内的 MediaPipe Gesture Recognizer。`LocalMediaServer` 仅监听随机的 `127.0.0.1` 端口，向同一进程内的 WKWebView 提供 JavaScript、WASM 和模型文件。

识别器配置为单手模式，优先使用 GPU，输出：

- 21 个镜像后的手部关键点；
- `Left` / `Right` 左右手分类；
- `Open_Palm`、`Pointing_Up`、`Victory`、`Thumb_Up` 等内置姿态；
- 分类置信度、推理耗时和实时 FPS。

如果 MediaPipe 无法启动，App 会降级到 Apple Vision。备用模式保留基础关键点、滚动和翻页，但不发送依赖 MediaPipe 分类稳定性的鼠标事件。

## 手势状态机

`GestureControlCore` 不依赖 SwiftUI、摄像头或系统权限，因此可以用固定关键点数据做快速单元测试。

核心规则：

- 严格 OK：拇指食指接触，其他三指张开；接触和释放使用不同阈值，避免临界抖动。
- 方向锁：OK 捏合后先判断水平或垂直主导，锁定后直到松手都不会切换。
- 垂直锁：连续输出归一化滚动增量；丢手或松开立即结束。
- 水平锁：合法侧边起手后第一次到达屏幕中线就输出一次导航。
- 张掌翻页：读取约 `360ms` 的手掌中心轨迹，要求水平位移和水平主导，并带冷却与重新激活。
- 食指指针：严格食指姿态稳定后输出 `indexTip`；小移动做死区过滤，异常单帧跳变直接丢弃。
- 食指点击：指针停稳后检测拇指中指接触；持续接触只点击一次，释放后才可重新点击。
- 控制手过滤：只有用户选择的左手或右手能进入状态机。

## 系统输出层

所有系统事件都要求辅助功能权限，并且只发送给当前前台应用。

- `SystemScrollEmitter`：通过 `.cghidEventTap` 发送像素滚动与离散翻页事件。
- `SystemNavigationEmitter`：只对 Chrome、Safari、Edge、夸克发送 `Command + [` 或 `Command + ]`。
- `SystemPointerEmitter`：只在上述浏览器中映射主屏幕鼠标，使用独立 `.privateState` 事件源发送无修饰键左键，避免继承 Command 等键盘状态。

切换前台 App、切换控制手、暂停、停止识别或丢手时，`AppModel` 会取消当前活动手势，防止旧状态落到新窗口。

## UI 与反馈层

App 同时提供 SwiftUI Dock 窗口和菜单栏入口。全屏反馈由两个非激活 `NSPanel` 组成：

- 骨架层完全点击穿透，绘制镜像骨架、黄色控制点和跨线闪光；
- 状态层显示当前动作，可收进右边缘，也可双击暂停或恢复。

关闭骨架只隐藏调试连线，不隐藏真正影响操作的黄色控制点和导航确认闪光。

## 隐私边界

- 不保存摄像头帧或关键点。
- 不上传识别数据。
- 不读取网页 DOM 或屏幕像素。
- 不申请屏幕录制或输入监控。
- 本机 loopback 服务只在识别运行期间存在，不监听局域网地址。

## 质量门

```bash
npm run typecheck
npm test
npm run build

cd macos-app
swift test
swift run GestureControlCoreChecks
./scripts/package-release.sh
```

发布包还需要验证 Universal 架构、Info.plist、ad-hoc 签名、designated requirement、DMG 实际挂载内容和 SHA-256。
