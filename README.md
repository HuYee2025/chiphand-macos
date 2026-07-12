# 黑洞手势控制 Web Demo

《火星先遣队》无限循环黑洞的独立交互实验。使用摄像头识别一只手：

- 手掌上下左右移动：控制黑洞视角。
- 手掌保持向左或向右旋转：黑洞会向对应方向持续旋转；手掌回正后停止。
- 手掌靠近摄像头：黑洞前进更快；远离摄像头：前进更慢。首次识别约 0.6 秒自动校准为 1× 速度。
- 张开手掌：继续前进。
- 握拳：暂停。
- 左手骨架为红色，右手骨架为蓝色。

## 本地运行

```bash
npm install
npm run dev
```

打开终端显示的 localhost 地址，点击“启动摄像头”并授权。首次安装会把 MediaPipe WASM 和 `HandLandmarker` 模型准备到 `public/mediapipe/`，运行时不依赖 CDN。

追踪采用 GPU 优先、CPU 自动备用、约 24–30 FPS 自适应检测；短暂遮挡会保留最后一个可信手势约 220ms，避免关键点瞬间消失。

## 验证

```bash
npm run typecheck
npm test
npm run build
npm run preview
```

摄像头只能在 HTTPS 或 localhost 环境使用。拒绝权限或没有摄像头时，可以使用鼠标/触控控制方向，按空格键暂停或继续。
