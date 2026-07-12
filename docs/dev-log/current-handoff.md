# 当前交接

新对话默认先读：
1. `AGENTS.md`
2. `docs/project-management.md`
3. `docs/production-blueprint.md`
4. `docs/dev-log/current-handoff.md`
5. `docs/tech-plan.md`
6. `docs/decision-log.md`

当前版本状态：
- 0.1.0 MVP 已完成；第 02 阶段等待用户实机调手感。
- 已补齐 `VERSION`、`CHANGELOG.md` 和 `versions/v0.1.0/version.json`，用于 GitHub 首次发布和后续回滚。
- GitHub 仓库：`https://github.com/HuYee2025/black-hole-gesture-control`。

最近完成：
- 独立 Vite/TypeScript/Three.js 工程和本地 MediaPipe 资源流程。
- 单手 21 点骨架、左右手红蓝、位置转向、持续手掌旋转、距离调速、张手继续和握拳暂停。
- HandLandmarker float16、GPU 优先 CPU 备用、24–30 FPS 自适应、逐点平滑和 220ms 丢失续帧。
- 摄像头小窗显示/隐藏、鼠标触控备用、手机响应式布局。

当前未完成：
- 用户确认极端侧面、拇指收拢、竖直手掌、持续旋转和距离调速的实机体验。
- Windows 与手机真机验证。
- 如需对外分享，再选择 HTTPS 静态部署。

本次验证：
- `npm run typecheck` 通过。
- `npm test`：12/12 通过。
- `npm run build` 通过。
- Mac 真实摄像头：右手蓝色骨架、握拳暂停验证通过；HandLandmarker GPU Worker 后约 60 FPS。
- 桌面 1200×720 与手机 390×844 布局检查通过。

下一步建议：
- 让用户运行 `npm run dev`，实际左右转动手掌并前后移动，反馈旋转方向和调速范围是否需要微调。
- 根据体感只调整 `src/tunnel-controller.ts` 的偏转/旋转幅度和 `src/input-controller.ts` 的死区。

重要限制：
- 摄像头正式部署要求 HTTPS；localhost 可用。
- 不修改 `/Users/huyi/Documents/游戏制作研究`。
- `public/mediapipe/` 为自动生成资源，不手工维护。
- `摄影头识别手部识别参考/` 和 `黑洞试验Dome/` 是本地参考资料，不作为运行文件上传到 GitHub。

不要重复做：
- 不要把 MediaPipe 推理移回主线程；已实测会明显降低 FPS。
- 不要换回 GestureRecognizer；当前控制只依赖 HandLandmarker 关键点和本地几何判断。
- 不要把当前 Demo 合并回《火星先遣队》，除非用户另行决定。
