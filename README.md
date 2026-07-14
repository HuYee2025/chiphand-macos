# 手势浏览控制

使用 MacBook 摄像头识别单手手势，控制 Chrome 网页滚动。所有摄像头画面、手部关键点和模型推理都只在本机运行。

## Chrome 插件

- 向左挥：页面向上滚动约 75% 屏幕。
- 向右挥：页面向下滚动约 75% 屏幕。
- 只有张开手掌的快速挥动会触发；一次挥动只执行一次。

### 构建和安装

```bash
npm install
npm run build:extension
```

1. 打开 `chrome://extensions/`。
2. 开启“开发者模式”。
3. 点击“加载已解压的扩展程序”。
4. 选择本项目的 `dist-extension/` 文件夹。
5. 打开普通网页，点击插件图标；它会弹出独立的手势控制窗口。
6. 在控制窗口点击“启动摄像头”。

授权完成后，控制窗口保留实时摄像头预览，识别转入 Chrome 后台页面：你可以直接点击和浏览网页，识别不会中断。控制窗口会贴近网页右侧入口；鼠标停留在窗口内时始终保持打开，只有移出窗口后才会自动关闭。关闭后会重新确认网页控制链路。Chrome 只会在首次授权时弹窗；此前已经允许时会直接启动。拇指与食指近乎贴合约 0.1 秒后，上下移动手即可连续滚动网页：手向上拖会看到下方内容，手向下拖会看到上方内容，稍微分开手指就立即停止。张开手掌向左挥会向上滚一屏，向右挥会向下滚一屏。网页默认不显示捏合点或手部网格，左右挥动时才在中央短暂显示空心上下箭头。右侧保留一个 28px 黑色圆点，点击可重新打开摄像头预览。控制窗口按钮下方始终显示“高级设置”：可调整左右挥手、手指捏合灵敏度，也可按需开启网页手部网格或捏合圆点；设置只保存在本机。

### 打包与 Edge

```bash
npm run package:extension
```

命令会生成 `releases/gesture-browser-control-v1.0.0.zip`，用于提交 Chrome Web Store 或 Microsoft Edge Add-ons。日常本机安装仍应选择解压后的 `dist-extension/` 文件夹，而不是 ZIP。

Microsoft Edge（Chromium 版）可直接兼容这一份 MV3 扩展：在 `edge://extensions/` 开启“开发人员模式”，选择“加载解压缩的扩展”，再选 `dist-extension/`。发布到商店时，Chrome Web Store 与 Microsoft Edge Add-ons 分别提交同一份 ZIP 和各自的商店资料。

插件只申请 `activeTab`、`scripting` 和 `offscreen`。控制窗口只负责首次请求摄像头权限；后台页面负责持续识别，网页内提示条负责反馈。切换到新标签页后，需要在新页面再次点击插件图标授权。Chrome 内置页面、Chrome 应用商店等受保护页面无法控制。

上下滚动为通用动作；本版本不再发送 JavaScript 合成方向键。

## 验收页面

```bash
npm run dev
```

打开 `http://127.0.0.1:5173/gesture-test.html`，可以验证捏合下翻、左右挥动上下翻、单次触发和输入框保护。

## 黑洞手势 Demo

根地址仍保留原有 Three.js 黑洞实验，用于验证手部追踪、位置转向、手掌旋转、距离调速、张手继续和握拳暂停。

```bash
npm run dev
```

打开终端显示的根地址。摄像头只能在 HTTPS 或 localhost 环境使用。

## 质量门

```bash
npm run typecheck
npm test
npm run build
```

`npm run build` 同时生成 `dist/` Web Demo 和 `dist-extension/` Chrome 插件。
