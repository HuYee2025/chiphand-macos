# 参与贡献

感谢你愿意改进薯片手。这个项目优先接受可复现的 Bug、浏览器兼容性修复、手势稳定性改进和清楚的小功能。

## 报告问题

提交 Bug 前请先确认：

1. 使用的是最新 Release，App 位于 `/Applications/薯片手.app`。
2. macOS 的摄像头和辅助功能权限都已允许。
3. 主窗口“测试系统下翻”是否有效。
4. 问题能否稳定复现，以及发生在哪个应用、浏览器和页面。

请使用仓库的 Bug 模板，并提供 macOS 版本、Mac 芯片、薯片手版本、目标应用、所选控制手、具体动作和复现步骤。不要上传包含私人内容的摄像头截图或录屏。

## 开发环境

- macOS 14+
- Xcode 26 或兼容的 Swift 6 工具链
- Node.js 24+ 与 npm

```bash
npm ci
npm run typecheck
npm test
npm run build

cd macos-app
swift test
swift run GestureControlCoreChecks
./scripts/build-app.sh
```

## 修改原则

- 不降低严格 OK 的防误触门槛来换取表面灵敏度。
- 丢手、切换 App、暂停或权限失效时，系统事件必须立即停止。
- 新系统事件必须有明确白名单和用户可见反馈。
- 不新增屏幕读取、云端识别、遥测或摄像头数据上传。
- 手势算法尽量放在 `GestureControlCore`，并补单元测试。
- UI、构建或权限行为变化要同步更新 README、用户说明和 CHANGELOG。

## Pull Request

PR 请保持单一目的，并写清：改了什么、为什么改、用户影响、验证命令和实机测试结果。涉及手感的改动，请注明没有回归张掌翻页、严格 OK、食指跟踪、单手选择、暂停和权限流程。

提交信息建议使用简洁的 Conventional Commits，例如：

```text
fix(macOS): stop scroll immediately when hand is lost
docs: clarify Gatekeeper installation steps
```
