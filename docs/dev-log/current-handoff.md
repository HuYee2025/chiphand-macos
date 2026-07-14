# 当前交接

新对话默认先读：
1. `AGENTS.md`
2. `docs/project-management.md`
3. `docs/production-blueprint.md`
4. `docs/dev-log/current-handoff.md`
5. `docs/tech-plan.md`
6. `docs/decision-log.md`

当前版本状态：
- `1.0.1` Chrome / Microsoft Edge（Chromium）手势浏览插件已完成可交付构建：独立控制窗口完成首次摄像头授权和实时预览，再由 Offscreen Document 持续识别；捏合上拖连续下翻，左挥上翻、右挥下翻。网页默认不显示捏合点或手部网格；“高级设置”始终显示在启停按钮下方，可按需开启两项调试叠层。默认原生窗口为 300×390，避免高级设置被底部裁切。窗口只在鼠标移出范围后收起，失焦不会关闭；控制窗口关闭时会恢复网页接收器和后台状态，入口在展开态隐藏。
- `v0.1.0` 是原始 Demo 回滚点；`v0.2.0` 保存 Chrome 插件 MVP，`v0.2.1` 保存启动顺序修复，`v0.3.0` 保存控制窗口架构。
- GitHub 仓库：`https://github.com/HuYee2025/black-hole-gesture-control`。

最近完成：
- 新增 `SwipeDetector`：360ms 轨迹、16% 位移、1.4 主轴比、650ms 冷却、稳定/离手重新激活。
- 新增 Chrome MV3 控制窗口、Offscreen Document、Service Worker、动态 Content Script 和最小权限。
- 捏合上拖连续下翻；左挥上滚、右挥下滚各 75% 视口；输入框获得焦点时忽略动作。
- 新增 `gesture-test.html`，用于确定性验证滚动、翻页和输入保护。
- `npm run build` 同时生成 `dist/` 与 `dist-extension/`。
- 识别到 macOS Chrome Side Panel 无法请求摄像头；改为由独立控制窗口请求权限，并透传原网页 tabId。
- 摄像头与 HandLandmarker 已迁入 Offscreen Document；控制窗口失焦或关闭时，后台识别仍继续。
- 网页内右侧入口缩为 28px 黑色圆点；识别到横挥时，在网页中央短暂显示对应的绿色空心上下箭头。
- 控制窗口恢复实时摄像头预览；鼠标停在窗口内不收起，只在移出后收起。
- 修复后台识别已经运行时重新打开控制窗口没有预览的问题。
- Offscreen 识别改用独立定时轮询，避免后台页面不产生视频/动画帧回调而导致手势不触发；新增“已检测到手掌 / 正在寻找张开的手掌”状态。
- 后台识别每秒最多同步 15 次关键点到控制窗口，实时预览恢复 21 点骨架连线。
- 新增 `PinchScrollDetector`：捏合稳定 80ms 后向网页连续发送上下滚动量；松开、手丢失或突跳时立即停；左右挥动保留，上下挥动禁用。
- 删除旧紧凑控制标签，避免控制窗口与网页内提示同时显示两个黑块。
- 网页内入口可直接打开关联网页的控制窗口。
- 捏合拖动改为手向上拖、查看下方内容；网页端仅显示镜像映射的半透明绿色捏合中点。
- 左挥改为上滚、右挥改为下滚；网页中央显示不遮挡正文的绿色空心上下箭头，控制窗口删除动作屏。
- 捏合判定收紧为 `0.18`，新增“近乎贴合触发、略分开取消”的单元测试；网页点改为不透明 36px、带极轻投影，并提升到 30 FPS 同步 + rAF 插值。
- 控制窗口压缩为 300×400、16:9 预览和圆形启停按钮；打开时贴近网页右侧入口，入口随控制窗口展开/收起过渡。
- 捏合点收口为 28px 无投影反色圆点（`mix-blend-mode: difference`），与入口同尺寸；控制窗口进一步收紧为 300×350、满宽圆角文字启停按钮，右缘贴齐并遮住入口。
- 反色点移出 Shadow DOM，改用 Light DOM 的 `backdrop-filter: invert(1)`；控制窗口关闭时主动恢复网页接收器与后台状态，修复关闭预览后动作失效。
- 新增可折叠高级设置：左右挥手和手指捏合灵敏度各有 0–100 滑杆，本机持久化并立即同步后台；默认 50 保持历史阈值。
- 网页调试叠层默认关闭；摄像头启动后才显示“高级模式”，可按需开启手部网格或捏合圆点，设置会与网页脚本同步。
- 修复网页手部网格启用后手势动作失效：Content Script 现在只接收 Service Worker 明确发给网页的消息。
- 修复控制窗口报 `Receiving end does not exist`：网页控制脚本现在独立注入、注入后 ping 确认；页面刷新后动作会自动补注入。

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
- `0.7.1` 消息路由修复的 `npm run typecheck`、27 项 `npm test`、`npm run build` 均已通过；需要用户在 Chrome 重新加载扩展并刷新测试页后验收。
- `0.7.2` 接收器恢复修复的 `npm run typecheck`、27 项 `npm test`、`npm run build` 均已通过；构建产物已额外确认 `content-script.js` 无运行时 import。用户必须重新加载扩展并刷新测试页后验收。
- `0.8.0` 网页极简反馈与横挥上下滚动的 `npm run typecheck`、27 项 `npm test`、`npm run build` 均已通过；构建产物确认无运行时 import、无合成方向键、无手部网格。测试页已用真实浏览器检查布局。
- `0.9.0` 严格捏合与紧凑窗口的 `npm run typecheck`、28 项 `npm test`、`npm run build` 均已通过；待用户真实 Chrome 验收圆点流畅度、捏合误触和窗口贴边位置。
- `0.9.1` 反色点与控制窗口收口的 `npm run typecheck`、28 项 `npm test`、`npm run build` 均已通过；300×350 静态控制界面已检查，待用户真实 Chrome 验收。
- `0.10.0` 反色、关闭恢复与高级设置的 `npm run typecheck`、31 项 `npm test`、`npm run build` 均已通过；300×350 收起、300×540 展开的静态控制界面已检查，待用户真实 Chrome 验收。
- `0.11.0` 默认隐身叠层与高级模式开关的 `npm run typecheck`、32 项 `npm test`、`npm run build` 均已通过；300×350 未启动、300×640 高级模式的静态控制界面已检查，待用户真实 Chrome 验收。
- `1.0.0` 修复高级设置被摄像头状态隐藏与窗口失焦提前关闭；`npm run typecheck`、32 项 `npm test`、`npm run build`、`npm run package:extension` 全部通过。商店 ZIP 的 `manifest.json` 已确认位于根目录；静态界面确认未启动时仍能看到“高级设置”，展开后可见四项开发者设置。
- `1.0.1` 修复 1.0.0 的原生窗口高度仍为 350px，导致高级设置入口被底部裁切；默认高度升至 390px。

当前未完成：
- 用户在目标 MacBook Chrome 或 Edge 重新加载 `dist-extension/`，刷新测试页，从网页右侧小黑圆点或插件图标打开控制窗口，再用真实手掌测试严格捏合和左右挥动上下滚动。
- 用户确认点击网页后后台识别仍持续，控制窗口关闭后仍能捏合/挥动控制页面；网页默认没有圆点或网格。展开始终可见的“高级设置”后，将两条滑杆调到 30 与 70 并打开对应叠层，确认设置立即生效。严格捏合时，若启用圆点才出现反色点，手指略分开时点应立刻消失。手向上拖能查看下方内容；右挥显示 `↓` 并下滚，左挥显示 `↑` 并上滚。
- 用户确认控制窗口右侧入口不再同时可见，点击网页后窗口关闭、圆点回弹；“关闭摄像头”满宽按钮可用。
- 记录 10 次捏合启停、右挥下翻、左挥上翻成功率，以及两分钟静止误触。
- 需要用户提供 Chrome 扩展页“错误”面板里的具体文本，才能确定旧版 `0.11.0` 的后台异常根因；截图中的红色按钮只是通用告警，不包含错误正文。
- 未得到发布请求前不要推送 GitHub 或发布 Chrome Web Store / Microsoft Edge Add-ons。

下一步建议：
- 在 `chrome://extensions/` 或 `edge://extensions/` 对此扩展点击重新加载，然后刷新 `http://127.0.0.1:4173/gesture-test.html`；确认版本显示为 `1.0.1`。不启动摄像头时，“高级设置”已完整显示在启停按钮下方；展开后应出现两条滑杆和两个开发者开关。启动后鼠标留在窗口内，窗口不得消失；移出窗口后才收起。关闭窗口后，仍须能向上捏合拖动、右挥下滚与左挥上滚。点击小黑圆点确认紧凑预览贴边打开，窗口展开时不应再看到第二个黑点。
- 商店发布时，使用 `releases/gesture-browser-control-v1.0.1.zip`；本机安装仍选择 `dist-extension/`，不要选择 ZIP。
- 如真实 Chrome 中 Offscreen Document 的摄像头授权行为有差异，优先调整首次授权和后台接力顺序，不退回依赖前台控制窗口的架构。

重要限制：
- Chrome 受保护页面不可注入；新标签页需要再次点击插件图标打开新的控制窗口。
- 当前版本不执行合成键盘事件；未来站点级翻页需单独适配。
- 摄像头画面、关键点和模型推理全部留在本机。
- `public/mediapipe/`、`dist/`、`dist-extension/` 是生成目录，不手工维护或提交。

不要重复做：
- 不要把 MediaPipe 推理移回主线程。
- 不要换回 GestureRecognizer；离散挥动继续使用 HandLandmarker 轨迹。
- 不要把 Chrome 插件改成全局 Mac 控制，除非浏览器版先通过用户验收。
