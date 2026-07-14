# 技术方案

## 技术栈

- Vite 8 + TypeScript 6。
- Three.js 0.185：虫洞渲染。
- `@mediapipe/tasks-vision` 0.10.35：`HandLandmarker` 21 点关键点和左右手识别。
- Chrome Manifest V3、独立控制窗口、Offscreen Document、`activeTab`、`scripting`、`offscreen`。
- 原生 DOM/CSS、Web Worker、`getUserMedia`。

## 架构/模块

- `TunnelController`：虫洞生成、循环、暂停、视角和整体旋转。
- `HandTracker`：摄像头生命周期、独立定时轮询驱动的 24–30 FPS 自适应抽帧、220ms 丢失续帧、逐点平滑和 Worker 通信；不依赖可见窗口动画帧。
- `gesture-worker`：在工作线程加载 `HandLandmarker`；GPU 优先，CPU 自动备用。
- `hand-gesture-math`：用关节距离判断张手、握拳和拇指食指捏合，并计算两指中点，不依赖内置手势分类标签。
- `InputController`：位置映射、10% 中央死区、6° 旋转死区、首次出现校准旋转零点和平滑；手掌倾斜量映射为持续旋转速度。
- `HandDistanceCalibrator`：以手腕到掌指关节的平均画面尺寸估算相对距离，首次约 0.6 秒校准，输出平滑的 0.45×～2.4× 前进倍率。
- `CameraOverlay`：镜像摄像头和红蓝手部骨架；Extension 后台每秒 15 次同步关键点给控制窗口预览，仅在本机扩展上下文传递。
- `PinchScrollDetector`：拇指食指接触稳定 80ms 后接管垂直控制；接触/释放阈值采用迟滞，连续输出受跳变保护的归一化拖动量。网页侧将其反向映射为文档滚动，遵循“手向上拖、查看下方内容”。
- `SwipeDetector`：保存最近 360ms 手掌中心轨迹；Extension 仅启用左右方向翻页，保留 650ms 冷却和稳定/离手重新激活。
- Extension 控制窗口：负责首次请求摄像头权限、实时预览、显示启动状态和停止控制；后台识别已运行时重新打开窗口会自动恢复预览。窗口只包含视频、单一动作屏和控制按钮；鼠标离开后直接关闭，失焦或关闭不停止后台识别。
- Extension Offscreen Document：持有 `HandTracker`、`SwipeDetector` 和摄像头轨道；不依赖可见 Chrome 窗口，持续把动作发送给关联网页。
- Offscreen 识别状态：看到手掌时向控制窗口和网页内提示条报告左右手与置信度；未看到时明确报告“正在寻找张开的手掌”。
- Extension Service Worker：在插件图标点击时绑定当前网页、动态注入网页控制脚本、创建 Offscreen Document，并转发后台状态和动作反馈。
- 网页内状态提示：通过 Content Script 固定在受控网页右侧；始终为 88×88 的黑色正方形，识别动作时短暂显示对应绿色大箭头；点击可重新打开关联标签页的控制窗口。网页同时按镜像坐标绘制 21 点手部网格，捏合时在两指中点绘制黄色指针球。
- `PageActionAdapter`：通用适配器负责离散动作；捏合滚动按实际网页视口高度执行连续 `scrollBy()`，左右仍发送 ArrowLeft / ArrowRight；站点适配器后续按注册顺序扩展。

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

- 静态 Web 应用，部署必须提供 HTTPS 才能使用摄像头。
- `predev`、`prebuild` 会把 MediaPipe WASM 和模型同步到本地静态资源目录。
- `dist/` 为黑洞 Demo 与验收页；`dist-extension/` 为可加载的 Chrome 解压扩展。
- Extension 使用 Chrome 114+，只申请 `activeTab`、`scripting`、`offscreen`，不申请 `<all_urls>`。
- 当前未发布 Chrome Web Store；通过 `chrome://extensions/` 加载 `dist-extension/`。

## 技术限制

- MediaPipe 控制台会输出 WebGL 初始化和 `NORM_RECT` 警告，已确认不影响识别。
- Three.js 主包构建后约 539 kB，Vite 会给出 chunk 体积警告，但不影响构建与 60 FPS 实测。
- Windows 与手机尚需对应真机验收。
- Chrome 内置页、Chrome Web Store 等受保护页面禁止脚本注入。
- 左右翻页使用合成 KeyboardEvent，`isTrusted` 为 false；拒绝合成事件的网站需要专用适配器。
