# 当前交接

新对话默认先读：
1. `AGENTS.md`
2. `docs/project-management.md`
3. `docs/production-blueprint.md`
4. `docs/dev-log/current-handoff.md`
5. `docs/tech-plan.md`
6. `docs/decision-log.md`

当前版本状态：
- `0.7.0` Chrome 手势浏览插件以独立控制窗口完成首次摄像头授权和实时预览，再由 Offscreen Document 持续识别；捏合拖动已按触控板直觉反转，张手仅保留左右翻页。网页右侧黑色方形可点击打开预览；窗口关闭后网页显示手部网格和黄色捏合指针；第 03 阶段等待用户真实手势验收。
- `v0.1.0` 是原始 Demo 回滚点；`v0.2.0` 保存 Chrome 插件 MVP，`v0.2.1` 保存启动顺序修复，`v0.3.0` 保存控制窗口架构。
- GitHub 仓库：`https://github.com/HuYee2025/black-hole-gesture-control`。

最近完成：
- 新增 `SwipeDetector`：360ms 轨迹、16% 位移、1.4 主轴比、650ms 冷却、稳定/离手重新激活。
- 新增 Chrome MV3 控制窗口、Offscreen Document、Service Worker、动态 Content Script 和最小权限。
- 上下动作滚动 75% 视口；左右动作发送 ArrowLeft / ArrowRight；输入框获得焦点时忽略动作。
- 新增 `gesture-test.html`，用于确定性验证滚动、翻页和输入保护。
- `npm run build` 同时生成 `dist/` 与 `dist-extension/`。
- 识别到 macOS Chrome Side Panel 无法请求摄像头；改为由独立控制窗口请求权限，并透传原网页 tabId。
- 摄像头与 HandLandmarker 已迁入 Offscreen Document；控制窗口失焦或关闭时，后台识别仍继续。
- 网页内右侧提示固定为 88×88 黑色方形；识别到动作时，短暂显示对应的绿色大箭头。
- 控制窗口恢复实时摄像头预览；鼠标停在窗口内不收起，只在移出后收起。
- 修复后台识别已经运行时重新打开控制窗口没有预览的问题。
- Offscreen 识别改用独立定时轮询，避免后台页面不产生视频/动画帧回调而导致手势不触发；新增“已检测到手掌 / 正在寻找张开的手掌”状态。
- 后台识别每秒最多同步 15 次关键点到控制窗口，实时预览恢复 21 点骨架连线。
- 新增 `PinchScrollDetector`：捏合稳定 80ms 后向网页连续发送上下滚动量；松开、手丢失或突跳时立即停；左右挥动保留，上下挥动禁用。
- 删除旧紧凑控制标签，避免控制窗口与网页内提示同时显示两个黑块。
- 网页内方形提示现在可直接打开关联网页的控制窗口；控制窗口移除四方向按钮阵列，动作发生时仅在黑色动作屏闪一个绿色箭头。
- 捏合拖动改为手向上拖、查看下方内容；网页端新增镜像映射的 21 点手部网格和黄色捏合中点指针。

本次验证：
- `npm run typecheck` 通过。
- `npm test`：20/20 通过，包含每方向 10 次轨迹和两分钟静止抖动模拟。
- `npm run build` 通过，模型、WASM、控制窗口、Offscreen Document、Service Worker 和 Content Script 产物齐全。
- Playwright 真实 Chromium：测试页布局、ArrowLeft / ArrowRight 页码变化和页面滚动通过。
- `0.4.3` Offscreen 取帧修复和手掌检测状态通过 TypeScript、20 项手势测试及完整构建；真实 Chrome Offscreen 手势仍需用户 MacBook 验收。
- `0.4.4` 方形网页提示和骨架预览恢复尚待运行完整质量门与用户 Chrome 验收。
- `0.5.0` 捏合滚动新增 6 项单元测试（总计 26 项）；`npm run typecheck`、`npm test`、`npm run build` 和本地测试页 HTTP 200 均已通过，真实 Chrome 手感验收待用户完成。
- `0.5.1` 删除紧凑窗口逻辑后，`npm run typecheck`、26 项 `npm test`、`npm run build` 和本地测试页 HTTP 200 均已通过；待用户确认离开控制窗口只留下网页方形提示。
- `0.6.0` 网页方形入口与精简控制窗口的 `npm run typecheck`、26 项 `npm test`、`npm run build` 和本地测试页 HTTP 200 均已通过；待用户确认点击方形可打开视频、点击网页后仍只剩方形反馈。
- `0.7.0` 反向捏合滚动与网页手势网格新增 1 项方向映射测试（总计 27 项）；`npm run typecheck`、`npm test`、`npm run build` 和本地测试页 HTTP 200 均已通过，待用户视觉验收。

当前未完成：
- 用户在目标 MacBook 上重新加载 `dist-extension/`，从测试页点击插件图标打开控制窗口，再用真实手掌测试四个方向。
- 用户确认点击网页后后台识别仍持续，控制窗口关闭后网页显示绿色手部网格和黄色捏合指针；手向上拖能查看下方内容。确认点击方形可重新打开视频，左右挥动正确。
- 记录 10 次捏合启停成功率、连续滚动稳定性、左右翻页成功率和两分钟静止误触。
- 收集拒绝合成左右方向键的网站，再添加站点适配器。
- 未得到发布请求前不要推送 GitHub 或发布 Chrome 商店。

下一步建议：
- 按 README 重新加载 `dist-extension/` 并刷新测试页；启动摄像头后点击网页，确认控制窗口关闭后仍显示绿色手部网格。捏住拇指食指约 0.1 秒，确认网页黄点出现；向上拖手确认页面显示下方内容。点击方形确认视频预览可重新打开，再张手左右挥动验证翻页。
- 如真实 Chrome 中 Offscreen Document 的摄像头授权行为有差异，优先调整首次授权和后台接力顺序，不退回依赖前台控制窗口的架构。

重要限制：
- Chrome 受保护页面不可注入；新标签页需要再次点击插件图标打开新的控制窗口。
- 合成 KeyboardEvent 的 `isTrusted` 为 false，左右翻页不是全站保证。
- 摄像头画面、关键点和模型推理全部留在本机。
- `public/mediapipe/`、`dist/`、`dist-extension/` 是生成目录，不手工维护或提交。

不要重复做：
- 不要把 MediaPipe 推理移回主线程。
- 不要换回 GestureRecognizer；离散挥动继续使用 HandLandmarker 轨迹。
- 不要把 Chrome 插件改成全局 Mac 控制，除非浏览器版先通过用户验收。
