# 当前交接

更新时间：2026-07-16。当前长对话已结束，下一对话从本文件继续，不需要读取旧聊天。

## 当前阶段

- 第 05 阶段：薯片手开源发布候选版。
- 当前版本：macOS `1.0.1 build 22`；公开候选版回滚点 `macos-v1.0.0`，重要稳定版 `macos-v0.3.0`。
- 当前分支：`codex/macos-system-prototype`。
- 暂不上传 GitHub；用户完成本机验收后再建立独立仓库。

## 已完成

- 产品正式命名为“薯片手 / ChipHand”，固定 bundle ID 为 `com.huyee.chiphand`。
- 正式图标为克莱因蓝底、放大金黄色薯片；菜单栏继续使用小手表示停止、运行和暂停。
- 主控制窗口完成蓝黄视觉改造，加入品牌文案、首次权限步骤、状态卡、手势速查和离线说明入口。
- `docs/user-guide/` 新增完全离线的响应式网页，包含安装、Gatekeeper 放行、权限、四种核心手势、反馈窗口、隐私和排障；四张手势插图为白底黑线并用蓝/黄标注动作。
- App 包含 MediaPipe JavaScript/WASM/模型、说明、MIT License 和 Apache 2.0 第三方许可，不需要最终用户安装任何开发工具。
- 构建改为 `arm64 + x86_64` Universal；新增 `package-release.sh` 生成 DMG、ZIP 和 SHA-256。
- 已安装 `/Applications/薯片手.app`。旧 `/Applications/GestureControl.app` 文件未删除，只停止进程以保留回滚。
- 删除“显示控制点”设置项；食指黄色控制点、鼠标跟随和拇指中指点击永久开启，旧版关闭记录在启动时自动清除。

## 本轮验证

- `swift test`：33 项通过。
- `swift run GestureControlCoreChecks`：22 项通过。
- `npm test`：32 项通过；`npm run typecheck` 通过。
- Universal warnings-as-errors Release 构建通过，二进制含 `arm64 x86_64`。
- Info.plist、严格 ad-hoc codesign、固定 designated requirement 均通过。
- DMG 实际挂载检查通过：App、Applications 快捷方式、内置模型、离线说明和许可文件齐全。
- `1.0.1` 安装版 UI 检查通过：只保留“全屏显示手掌骨架”和“显示摄像头校准窗口”两项复选框，不再出现“显示控制点”，底部版本为 `v1.0.1`。
- DMG/ZIP SHA-256 校验通过，安装版为 `1.0.1 build 22`，二进制含 `arm64 x86_64`，签名验证通过。
- Playwright 检查桌面和 390px 手机说明页，无缺图或布局溢出。
- 安装版控制窗口和图标通过 UI 检查；“使用说明”按钮已成功打开 App 包内 `file://.../UserGuide/index.html`。

## 本地测试产物

- `macos-app/releases/ChipHand-macOS-1.0.1-universal.dmg`
- `macos-app/releases/ChipHand-macOS-1.0.1-universal.zip`
- `macos-app/releases/SHA256SUMS.txt`
- `docs/user-guide/index.html`

## 尚需用户验证

- 新 bundle ID 第一次启动时完成摄像头与辅助功能授权，确认不再进入权限循环。
- 实机回归张掌翻页、严格 OK 上下滚动/跨中线导航、食指悬停与拇指中指点击。
- 主观验收 Dock 图标、控制窗口和图文说明；发现问题先修候选版。

## 下一步建议

1. 先接受用户下一条具体的实机反馈，检查当前安装版再修改，不重复搭建项目。
2. 细节优化必须保留食指跟踪流畅度、严格 OK 防误触、单手选择、反馈窗口和权限稳定性。
3. 修改后按风险运行 Swift/Web/Universal 构建与安装验证，并同步更新版本记录。
4. 用户确认后再建立独立公开仓库，建议仓库名 `chiphand-macos`，上传源代码与正式 Release。

## 最新归档

- `docs/dev-log/archive/05-chiphand-v1-candidate-checkpoint.md`
