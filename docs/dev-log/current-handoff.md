# 当前交接

新对话默认先读：
1. `AGENTS.md`
2. `docs/project-management.md`
3. `docs/production-blueprint.md`
4. `docs/dev-log/current-handoff.md`
5. `docs/tech-plan.md`
6. `docs/decision-log.md`

当前版本状态：
- `0.3.1` Chrome 手势浏览插件已改用独立控制窗口，以支持 macOS 摄像头授权；摄像头启动后 5 秒会缩为屏幕右侧窄标签；第 03 阶段等待用户真实手势验收。
- `v0.1.0` 是原始 Demo 回滚点；`v0.2.0` 保存 Chrome 插件 MVP，`v0.2.1` 保存启动顺序修复，`v0.3.0` 保存控制窗口架构。
- GitHub 仓库：`https://github.com/HuYee2025/black-hole-gesture-control`。

最近完成：
- 新增 `SwipeDetector`：360ms 轨迹、16% 位移、1.4 主轴比、650ms 冷却、稳定/离手重新激活。
- 新增 Chrome MV3 控制窗口、Service Worker、动态 Content Script 和最小权限。
- 上下动作滚动 75% 视口；左右动作发送 ArrowLeft / ArrowRight；输入框获得焦点时忽略动作。
- 新增 `gesture-test.html`，用于确定性验证滚动、翻页和输入保护。
- `npm run build` 同时生成 `dist/` 与 `dist-extension/`。
- 识别到 macOS Chrome Side Panel 无法请求摄像头；改为由独立控制窗口请求权限，并透传原网页 tabId。
- 新增控制窗口自动紧凑模式：启动后 5 秒缩成 92×142 的右侧标签，点击可展开，摄像头不中断。

本次验证：
- `npm run typecheck` 通过。
- `npm test`：20/20 通过，包含每方向 10 次轨迹和两分钟静止抖动模拟。
- `npm run build` 通过，模型、WASM、控制窗口、Service Worker 和 Content Script 产物齐全。
- Playwright 真实 Chromium：测试页布局、ArrowLeft / ArrowRight 页码变化和页面滚动通过。
- Playwright 控制窗口静态界面回归：紧凑模式只保留绿色状态点和“展开”按钮；真实 Chrome 扩展窗口尺寸和位置仍需用户 MacBook 验收。

当前未完成：
- 用户在目标 MacBook 上重新加载 `dist-extension/`，从测试页点击插件图标打开控制窗口，再用真实手掌测试四个方向。
- 用户确认紧凑标签在主显示器或外接屏上的位置符合预期；如需要真正贴边悬停自动探出，后续改为 macOS 原生菜单栏应用。
- 每方向 10 次成功率、重复触发次数、两分钟静止误触需要真实手势记录。
- 收集拒绝合成左右方向键的网站，再添加站点适配器。
- 未得到发布请求前不要推送 GitHub 或发布 Chrome 商店。

下一步建议：
- 按 README 重新加载 `dist-extension/`，启动摄像头并等待 5 秒，确认控制窗口缩为右侧窄标签后，在 `http://127.0.0.1:5173/gesture-test.html` 验收。
- 只根据真实体验调整 `src/swipe-detector.ts` 的位移、冷却和稳定阈值，不修改 HandLandmarker Worker 架构。

重要限制：
- Chrome 受保护页面不可注入；新标签页需要再次点击插件图标打开新的控制窗口。
- 合成 KeyboardEvent 的 `isTrusted` 为 false，左右翻页不是全站保证。
- 摄像头画面、关键点和模型推理全部留在本机。
- `public/mediapipe/`、`dist/`、`dist-extension/` 是生成目录，不手工维护或提交。

不要重复做：
- 不要把 MediaPipe 推理移回主线程。
- 不要换回 GestureRecognizer；离散挥动继续使用 HandLandmarker 轨迹。
- 不要把 Chrome 插件改成全局 Mac 控制，除非浏览器版先通过用户验收。
