# 第 04 阶段总结：macOS 系统级手势控制原型

本阶段目标：
- 把浏览器插件能力迁移为不依赖标签页的 macOS 全局手势控制。

完成内容：
- 从 Apple Vision 原型升级到 MediaPipe Gesture Recognizer，完成单手 21 点、本机 GPU、Apple Vision 备用与离线运行时。
- 完成张掌翻页、严格 OK 连续滚动、跨中线返回/前进、食指悬停与拇指中指点击、状态点赞和单手选择。
- 完成点击穿透骨架、黄色控制点、跨中线白线蓝光、可收起反馈条、双击暂停和摄像头校准。
- 修复辅助功能授权循环，建立固定 designated requirement；`macos-v0.3.0` 为重要稳定版，`macos-v0.8.6` 为品牌改造前完整回滚点。

关键决策：
- 系统级控制优先于继续扩展浏览器插件；识别和系统事件保持分层。
- 严格 OK 必须同时满足指尖接触和其余三指张开，减少握拳误触。
- 用户只选择一只控制手；MediaPipe 固定 `numHands: 1`。
- 不购买 Apple Developer 年费会员，转为 MIT 开源与本地 ad-hoc 打包路线。

重要文件：
- `macos-app/Sources/GestureControlCore/`
- `macos-app/Sources/GestureControlApp/`
- `docs/decision-log.md`

遗留问题：
- 真实用户首次下载仍需要一次 Gatekeeper 安全放行。
- 最终手势手感、权限引导和说明页仍需非开发者视角本机验收。

下一阶段建议：
- 以“薯片手 / ChipHand”完成品牌、完整安装包、离线说明和本地发布候选版；用户验收后再建立独立 GitHub 仓库。
