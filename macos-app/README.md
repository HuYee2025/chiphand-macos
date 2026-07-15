# macOS 系统手势控制原型

菜单栏 App 使用 Mac 摄像头和 Apple Vision 在本机识别单手手势，通过系统滚动事件控制前台应用。

## 当前动作

- 左挥：向上翻约 75% 屏幕。
- 右挥：向下翻约 75% 屏幕。
- 拇指与食指捏住后上下移动：连续滚动，松开或丢手立即停止。
- 不移动鼠标光标，不发送点击或键盘事件。

## 开发

建议安装完整 Xcode，然后执行：

```bash
cd macos-app
swift run GestureControlCoreChecks
./scripts/build-app.sh
open build/GestureControl.app
```

首次启动需要允许“摄像头”和“辅助功能”。本地原型使用 ad-hoc 签名，重新构建后 macOS 可能要求重新确认权限。
