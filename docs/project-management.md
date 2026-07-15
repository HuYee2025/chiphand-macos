# 项目管理

## 项目状态

- 当前阶段：第 04 阶段——macOS 系统级手势控制原型
- 当前版本：浏览器插件 `1.0.1` 已冻结；macOS 原型 `0.2.0`
- 当前目标：完成原生菜单栏 App 的摄像头/辅助功能授权与跨应用实机验收

## 阶段推进

| 阶段 | 状态 | 目标 | 交接/归档 |
| --- | --- | --- | --- |
| 01 | 已完成 | 独立黑洞手势控制 MVP | `docs/dev-log/archive/01-hand-control-demo.md` |
| 02 | 已收束 | 调整方向灵敏度、旋转手感和跨设备体验 | `docs/dev-log/archive/02-interaction-tuning-pivot.md` |
| 03 | 已收束 | Chrome 后台手势浏览插件 MVP | `docs/dev-log/archive/03-browser-extension-v1-pivot.md` |
| 04 | 进行中 | macOS 系统级菜单栏手势控制原型 | 等待权限与真实手势验收 |

## 岗位拆分

| 岗位 | 负责内容 | 当前状态 |
| --- | --- | --- |
| 产品/策划 | 方向、范围、优先级 | macOS 系统级原型为主线，浏览器插件冻结 |
| 开发 | 功能实现、修 Bug、验证 | macOS `0.2.0` 完整 21 点骨架、误识别过滤、动态状态和全屏 HUD |
| 内容/文案 | 设定、脚本、说明文字 | 菜单栏状态、权限说明和本地 README 已完成 |
| 美术/资产 | 图片、视觉、素材管理 | 使用系统菜单栏与 SF Symbols，暂不制作独立资产 |
| 发布 | GitHub、部署、版本说明 | 本地 ad-hoc `.app` 已生成；未签名发布或推送 GitHub |

## 当前任务

- 用“测试系统下翻”确认辅助功能与滚动输出链路。
- 在 Chrome、Safari、Preview、Notion 验证 21 点 HUD、左挥上翻、右挥下翻和捏住上下拖动滚动。

## 已完成

- Vite + TypeScript 独立工程。
- Three.js 无限循环黑洞迁入并模块化。
- HandLandmarker 单手控制、21 点骨架、左右手红蓝区分。
- 张手继续、握拳暂停、手掌位置转向、手掌旋转控制虫洞。
- 手掌距离摄像头越近前进越快，远离越慢；首次约 0.6 秒自动校准基准距离。
- HandLandmarker 推理迁入 GPU 优先的 Web Worker；逐点平滑和 220ms 丢失续帧；真实摄像头验证约 60 FPS。
- 建立 `0.1.0` 版本基线并发布到 GitHub。
- 完成 `SwipeDetector`、四方向动作、冷却和重新激活机制。
- 完成 Chrome MV3 控制窗口、最小权限、网页动作适配和输入保护。
- 完成自建浏览动作验收页和独立 Extension 构建。
- 建立 `0.2.0` 本地版本记录。
- 完成 macOS `0.1.0` 原型：AVFoundation、Apple Vision、系统滚动、菜单栏控制和权限引导。
- 新增 10 项纯 Swift 核心检查与可复现 `.app` 打包脚本。
- GitHub 仓库：`https://github.com/HuYee2025/black-hole-gesture-control`。

## 可循环任务

只记录边界清楚、可验证、可停止的任务。不要把开放式探索任务强行循环化。

| 任务 | 触发条件 | 验证方式 | 停止条件 | 状态 |
| --- | --- | --- | --- | --- |
| Web 构建与测试 | Web/Extension 代码变化后 | `typecheck`、`test`、`build` 全通过 | 全通过或连续失败 3 次 | 冻结备用 |
| macOS 构建与检查 | macOS 原型代码变化后 | 核心检查、Swift build、`.app` 签名全通过 | 全通过或连续失败 3 次 | 可用 |

## 决策记录

| 日期 | 决策 | 原因 | 影响 |
| --- | --- | --- | --- |
| 2026-07-12 | 独立 Web Demo，不改《火星先遣队》原项目 | 降低耦合，便于跨设备验证 | 当前根目录成为独立应用 |
| 2026-07-12 | MediaPipe 在 Web Worker 中运行 | 主线程方案实测最低约 19 FPS | 摄像头开启后恢复约 60 FPS |
| 2026-07-13 | 先做 Chrome Side Panel 插件 | 最大化复用现有 Web 识别引擎并降低 Mac 权限成本 | 新增 `dist-extension/` 构建 |
| 2026-07-15 | 主线转为 macOS 系统级原型 | 消除浏览器标签页和页面注入约束 | 新增 `macos-app/`，浏览器插件冻结 |

## 质量门

- 先查看项目已有命令：Node/前端项目看 `package.json` 的 `scripts`。
- 代码变更：优先运行已有 `build`、`test`、`lint`、`typecheck`。
- 多语言内容：优先运行已有 `i18n:audit`、`translate:check` 或同类翻译检查。
- 页面或交互：优先运行已有 `dev`/`preview`，检查真实页面效果。
- 没有现成命令时：把建议的验证方式补到 `docs/tech-plan.md`。

## 新对话交接检查

- 技术/UI 决策是否写入 `docs/tech-plan.md`。
- 重要取舍是否写入 `docs/decision-log.md`。
- 当前实现状态是否写入 `docs/dev-log/current-handoff.md`。
