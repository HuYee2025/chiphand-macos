# 技术方案

## 技术栈

### 当前主线：macOS 原型

- Swift 6.3 / SwiftUI `Window` + `MenuBarExtra`，部署目标 macOS 14+。
- WKWebView + `@mediapipe/tasks-vision` 0.10.35：主引擎使用 Gesture Recognizer，单手 21 点、左右手与内置姿态分类，GPU 优先。
- Network.framework：进程内只监听 `127.0.0.1`，向 WKWebView 提供打包在 App 内的 HTML、WASM 与模型。
- AVFoundation + Vision：MediaPipe 启动失败时的本机备用识别路径。
- Core Graphics `CGEvent`：通过 `.cghidEventTap` 注入连续滚动、翻页、受限浏览器导航，以及可选的食指鼠标移动与单击。
- ApplicationServices：检查辅助功能信任；AppKit `NSWorkspace`：跟踪前台 App 切换。

### 冻结分支：Web / Extension

- Vite 8 + TypeScript 6。
- Three.js 0.185：虫洞渲染。
- `@mediapipe/tasks-vision` 0.10.35：`HandLandmarker` 21 点关键点和左右手识别。
- Chrome Manifest V3、独立控制窗口、Offscreen Document、`activeTab`、`scripting`、`offscreen`。
- 原生 DOM/CSS、Web Worker、`getUserMedia`。

## 架构/模块

### macOS 原型

- `GestureControlCore`：平台无关的关键点归一化、严格 OK 捏合迟滞与方向锁、跨中线导航、张掌翻页，以及严格食指指针/停稳/拇指中指接触点击组合状态机；V 手势仅保留状态。
- `MediaPipeHandPoseService`：WKWebView 主识别运行时；接收完整 21 点、左右手、内置手势、置信度、推理耗时和 FPS，并可显示同源校准窗口。识别器固定 `numHands: 1`，校准层不绘制未选择手。
- `LocalMediaServer`：仅在 loopback 随机端口提供离线运行资源，避免 `file://` 对 ES Module、WASM 与摄像头安全上下文的限制。
- `CameraCaptureService` + `HandPoseService`：Apple Vision 备用路径；最多请求一只手，按结构与置信度连续跟踪。
- `AppModel`：权限、摄像头、手势状态和前台 App 目标的唯一协调者；持久保存右手/左手单选，只有所选手能进入 `GestureEngine`，App 切换或控制手切换立即取消活动手势。
- `SystemScrollEmitter`：捏合增量直接转为像素滚动；离散翻页拆成 12 个小事件，并从 HID event tap 注入到目标窗口中心。
- `SystemNavigationEmitter`：严格 OK 跨中线后按方向发送 `Command + [` 或 `Command + ]`；AppModel 只允许 Chrome、Safari、Edge 和夸克调用。
- `SystemPointerEmitter`：把镜像 `indexTip` 直接映射到主屏幕并发送 HID `mouseMoved`；定位后的拇指中指捏合直接复用严格 OK 的距离、释放阈值和稳定时间，在冻结点使用独立 `.privateState` 事件源发送一次无修饰键左键按下/松开。只在四个浏览器和辅助功能有效时启用。
- `MenuBarView`：启停、权限状态、两项灵敏度、右手/左手互斥选择、默认关闭的食指指针测试、全屏 HUD 与摄像头校准开关。
- `ScreenGestureOverlayController`：使用两个 `NSPanel`。全屏层只绘制点击穿透的镜像简化骨架、严格捏合圆点和点赞标记；状态层固定为底部居中 `390×52`，右侧三道杠将其收为右边缘 `30×44` 左圆右方迷你条。迷你条用 AppKit 屏幕绝对鼠标坐标只改变纵向位置；双击迷你条恢复默认帧，双击展开内容在暂停/恢复识别之间切换。
- 暂停状态：`AppModel.isPaused` 与完整停止分离；暂停会停止 MediaPipe、Apple Vision、摄像头和所有系统事件，隐藏骨架但保留红色反馈条。恢复前重新检查摄像头与辅助功能权限，不自动打开系统设置。
- 校准窗口：MediaPipe 主路径直接显示同一 WKWebView 的自拍镜像视频与骨架；Apple Vision 备用路径由 `DebugWindowController` 显示相同方向。
- 权限协调：启动按钮只记录启动意图，不再自动跳转系统设置；App 每秒刷新 Camera/Accessibility 状态，授权生效后自动继续启动。

### Web / Extension（冻结）

- `TunnelController`：虫洞生成、循环、暂停、视角和整体旋转。
- `HandTracker`：摄像头生命周期、独立定时轮询驱动的 24–30 FPS 自适应抽帧、220ms 丢失续帧、低延迟逐点平滑和 Worker 通信；不依赖可见窗口动画帧。
- `gesture-worker`：在工作线程加载 `HandLandmarker`；GPU 优先，CPU 自动备用。
- `hand-gesture-math`：用关节距离判断张手、握拳和拇指食指捏合，并计算两指中点，不依赖内置手势分类标签；默认捏合归一化距离阈值为 `0.18`，可由本机高级设置在 `0.12–0.24` 内微调。
- `InputController`：位置映射、10% 中央死区、6° 旋转死区、首次出现校准旋转零点和平滑；手掌倾斜量映射为持续旋转速度。
- `HandDistanceCalibrator`：以手腕到掌指关节的平均画面尺寸估算相对距离，首次约 0.6 秒校准，输出平滑的 0.45×～2.4× 前进倍率。
- `CameraOverlay`：镜像摄像头和红蓝手部骨架；Extension 后台每秒 15 次同步关键点给控制窗口预览，仅在本机扩展上下文传递。
- `PinchScrollDetector`：拇指食指接触稳定 80ms 后接管垂直控制；接触/释放阈值采用迟滞，连续输出受跳变保护的归一化拖动量。网页侧将其反向映射为文档滚动，遵循“手向上拖、查看下方内容”。
- `SwipeDetector`：保存最近 360ms 手掌中心轨迹；Extension 仅检测左右挥动，其中左挥映射上滚、右挥映射下滚，保留 650ms 冷却和稳定/离手重新激活。默认最小位移 `0.16`，可由本机高级设置在 `0.10–0.22` 内微调。
- Extension 控制窗口：负责首次请求摄像头权限、实时预览、显示启动状态和停止控制；后台识别已运行时重新打开窗口会自动恢复预览。窗口为 300×390、16:9 视频和满宽圆角的“开启摄像头 / 关闭摄像头”按钮；按钮下方始终显示可展开的“高级设置”，展开时窗口升至 300×640。高级设置包含左右挥手、手指捏合灵敏度滑杆，以及网页手部网格/捏合圆点两个调试开关。打开时右缘贴齐受控 Chrome 窗口；仅 `pointerleave` 会关闭窗口，窗口失焦不关闭也不停止后台识别；关闭时 Service Worker 再次确认网页控制脚本与后台状态。
- Extension Offscreen Document：持有 `HandTracker`、`SwipeDetector` 和摄像头轨道；不依赖可见 Chrome 窗口，持续把动作发送给关联网页。
- Offscreen 识别状态：看到手掌时向控制窗口和网页内提示条报告左右手与置信度；未看到时明确报告“正在寻找张开的手掌”。
- Extension Service Worker：在插件图标点击时绑定当前网页、动态注入网页控制脚本、创建 Offscreen Document，并转发后台状态和动作反馈。动态注入后必须 ping 确认网页接收器可用；页面跳转导致脚本消失时，下一次网页消息会补注入并只重试一次。
- 网页内状态提示：通过 Content Script 在受控网页顶层绘制，不阻挡网页点击。默认不画捏合点和手部网格；高级模式开启时，捏合点按镜像坐标在两指中点显示为 28px 反色圆，作为 Light DOM 节点直接使用 `backdrop-filter: invert(1)`，无固定颜色、无投影；手部网格绘制镜像 21 点骨架。松开即清空。后台按 30 FPS 同步状态，网页以 `requestAnimationFrame` 插值更新位置。左右挥动时在网页中央显示约 550ms 的空心绿色上下箭头。右侧仅保留同尺寸 28px 黑色圆点作为重新打开控制窗口的入口；入口下移，控制窗口开关时圆点做缩放淡入淡出。Content Script 是无运行时 import 的独立注入文件，并先筛选消息类型，只处理 Service Worker 直接转发的网页请求。
- `gesture-settings`：用 `chrome.storage.local` 保存 0–100 的左右挥手、手指捏合灵敏度和两个网页调试叠层开关；默认值严格等于原有阈值且两个叠层都关闭。设置修改会立即让 Offscreen Document 重建相应检测器，并同步网页叠层状态，不重启摄像头。
- `PageActionAdapter`：通用适配器负责离散动作；捏合滚动按实际网页视口高度执行连续 `scrollBy()`；左挥 / 右挥分别平滑上滚 / 下滚 75% 视口。

## 开发命令

```bash
npm install
npm run dev
npm run typecheck
npm test
npm run build
npm run build:demo
npm run build:extension
npm run preview

cd macos-app
swift run GestureControlCoreChecks
swift build --target GestureControlApp
./scripts/build-app.sh
open build/GestureControl.app
```

## 质量门

- 通用原则：先看项目已有命令，尤其是 `package.json` 的 `scripts`；存在什么跑什么，不硬造命令。
- 代码变更后：优先跑 `build`；如果项目有 `test`、`lint`、`typecheck`，也要按变更风险运行。
- 多语言/文案变更后：如果项目有 `i18n:audit`、`i18n:check`、`translate:check` 等命令，必须运行。
- 页面/视觉/交互变更后：启动 `dev` 或 `preview`，用真实页面检查效果；必要时截图或浏览器验证。
- 部署/发布前：至少跑构建命令，并确认产物目录、启动方式和环境变量没有变化。
- 如果当前项目还没有质量门命令：先在本文件记录建议命令，再继续推进。

## 循环任务规则

循环任务只用于边界清楚、结果可验证的重复工作，例如：构建失败修复、翻译审计修复、页面视觉回归检查、阶段交接整理。

每个循环任务必须先写清楚：

- 目标：要达到什么结果。
- 输入：本轮必须读取哪些文件。
- 动作：本轮允许改什么。
- 验证：运行哪些质量门或如何人工检查。
- 停止条件：什么时候停止，不继续消耗上下文。
- 写回位置：结果写入哪个项目文件。

默认停止条件：

- 质量门通过。
- 连续 2 轮没有实质变化。
- 同一问题失败 3 次。
- 需求不清楚，需要用户决策。
- 涉及删除、发布、账号、密钥、高风险部署等操作。

每轮结束后，必须把验证结果和下一步写回 `docs/dev-log/current-handoff.md` 或相关权威文件。

## 部署/发布

- macOS 原型通过 `macos-app/scripts/build-app.sh` 生成 `macos-app/build/GestureControl.app`；当前使用 ad-hoc 签名，只供本机测试。
- 正式分发前必须改用 Developer ID 签名、Hardened Runtime 和 notarization；当前阶段不执行。

### Web / Extension（冻结）

- 静态 Web 应用，部署必须提供 HTTPS 才能使用摄像头。
- `predev`、`prebuild` 会把 MediaPipe WASM 和模型同步到本地静态资源目录。
- `dist/` 为黑洞 Demo 与验收页；`dist-extension/` 为可加载的 Chrome 解压扩展。
- Extension 使用 Chrome 114+，只申请 `activeTab`、`scripting`、`offscreen`，不申请 `<all_urls>`。
- 当前可用 `npm run package:extension` 生成 `releases/gesture-browser-control-v1.0.1.zip`，用于 Chrome Web Store 和 Microsoft Edge Add-ons；本机仍通过 `chrome://extensions/` 或 `edge://extensions/` 加载 `dist-extension/`。

## 技术限制

- macOS 原型必须由用户在系统设置中授予摄像头和辅助功能权限；无权限时只显示状态，不发送事件。
- Xcode 26.6 已安装并接受 License；核心逻辑同时保留可执行检查和标准 `XCTest`。
- 当前 `.app` 使用 ad-hoc 签名，仅供本机原型；更改 bundle identifier 或签名 requirement 时系统权限仍需重新确认。
- 从 `0.4.1` 起 ad-hoc 签名包含固定 bundle identifier 的 designated requirement，避免 TCC 只绑定变化的 CDHash；首次升级需清理一次旧记录。
- Core Graphics 滚动方向、不同 App 的滚动响应和手势阈值仍需真实手势验收。
- MediaPipe 主运行时资源约 40 MB；只在本机 loopback 端口短暂提供，App 停止识别时关闭。

- MediaPipe 控制台会输出 WebGL 初始化和 `NORM_RECT` 警告，已确认不影响识别。
- Three.js 主包构建后约 539 kB，Vite 会给出 chunk 体积警告，但不影响构建与 60 FPS 实测。
- Windows 与手机尚需对应真机验收。
- Chrome 内置页、Chrome Web Store 等受保护页面禁止脚本注入。
- 浏览器返回/前进使用受 bundle allowlist 限制的 `Command + [` / `Command + ]`；其余网页控制仍不使用合成键盘事件。
