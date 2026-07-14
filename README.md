# 手势浏览控制

使用 MacBook 摄像头识别单手挥动，控制 Chrome 网页滚动和左右翻页。所有摄像头画面、手部关键点和模型推理都只在本机运行。

## Chrome 插件

- 向上挥：页面向上滚动约 75% 屏幕。
- 向下挥：页面向下滚动约 75% 屏幕。
- 向左挥：向网页发送 `ArrowLeft`，用于上一页。
- 向右挥：向网页发送 `ArrowRight`，用于下一页。
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

授权完成后，摄像头和识别会转入 Chrome 后台页面：你可以直接点击和浏览网页，识别不会中断。当前网页右侧会出现一个极细的黑色提示条；它不会因点击网页消失。鼠标悬停后会展开为状态提示，离开约半秒或停留 5 秒后收回。只有识别到挥动时，提示条才会短暂显示对应的绿色大箭头。

插件只申请 `activeTab`、`scripting` 和 `offscreen`。控制窗口只负责首次请求摄像头权限；后台页面负责持续识别，网页内提示条负责反馈。切换到新标签页后，需要在新页面再次点击插件图标授权。Chrome 内置页面、Chrome 应用商店等受保护页面无法控制。

部分网站会拒绝 JavaScript 合成的方向键事件；上下滚动为通用动作，左右翻页通过 `PageActionAdapter` 继续增加网站适配。

## 验收页面

```bash
npm run dev
```

打开 `http://127.0.0.1:5173/gesture-test.html`，可以验证上下滚动、左右翻页、单次触发和输入框保护。

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
