# Changelog

## 0.2.0 - 2026-07-13

- 新增 Chrome Manifest V3 手势浏览插件与常驻 Side Panel。
- 新增四方向离散挥动检测、650ms 冷却、稳定/离手重新激活和轨迹测试。
- 上下挥动滚动 75% 视口，左右挥动发送网页 ArrowLeft / ArrowRight 翻页动作。
- 新增网页动作适配层、输入框保护、最小权限和错误状态提示。
- 新增浏览动作验收页，以及独立的 Web Demo / Extension 构建目标。
- 验证：`npm run typecheck`、`npm test`、`npm run build`、真实 Chromium 测试页。

## 0.1.0 - 2026-07-13

- 建立黑洞手势控制独立 Web Demo。
- 完成 Three.js 无限循环黑洞、HandLandmarker 单手追踪、21 点骨架、左右手颜色区分。
- 完成手掌位置转向、手掌倾斜持续旋转、距离调速、张手继续和握拳暂停。
- 完成 MediaPipe 资源同步脚本，运行时从本项目同源加载 WASM 和模型资源。
- 验证：`npm run typecheck`、`npm test`、`npm run build`。
