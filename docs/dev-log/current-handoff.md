# 当前交接

## 当前阶段

- 第 04 阶段：macOS 系统级手势控制原型。
- 浏览器插件冻结在本地 `v1.0.1`；macOS 当前版本 `0.8.2`，`macos-v0.8.1` 为本轮修改前回滚点，`macos-v0.3.0` 为 ⭐ 重要稳定版。
- 当前分支：`codex/macos-system-prototype`。

## 已完成

- 主识别引擎升级为 MediaPipe Gesture Recognizer 0.10.35：单手、完整 21 点、左右手、`Victory`/`Thumb_Up` 等内置姿态、GPU 优先/CPU 备用；Apple Vision 仅作启动失败兜底。
- MediaPipe HTML、WASM 和模型全部打包在 App 内，由进程内 `127.0.0.1` 随机端口提供给 WKWebView；摄像头画面和关键点不保存、不上传。
- 校准视频、骨架和全屏 HUD 统一为自拍镜像；显示层使用腕点和每指 3 段，底层仍保留 21 点用于姿态与捏合判断。
- 支持左右手颜色、张掌/握拳/单指/捏合/翻页动态状态；真实捏合时显示拇指食指中点圆，松开即消失。
- 捏合改为严格 OK 手势：拇指食指接触且中指、无名指、小指张开；握拳和两指偶然靠近不会启动滚动。
- 严格 OK 捏合加入方向锁：垂直移动连续滚动；左侧向右跨中线返回，右侧向左跨中线前进，仅允许 Chrome、Safari、Edge、夸克。
- 张开手掌恢复左右挥动翻页：手掌中心向右达到水平距离即下翻，向左即上翻，不要求跨过屏幕中线；保留水平主导、650ms 冷却和离手/稳定后重激活。
- 食指与 V 手势只显示状态，不再发送翻页事件。
- 新增默认关闭的食指指针测试：四个浏览器中严格握拳竖食指移动真实鼠标；停稳后保持食指并用拇指中指轻捏执行一次单击，鼠标在退出后停留原位。
- 食指指针继续使用 150ms 激活、180ms 分类容错、约 24pt/350ms 定位、4pt 死区和 18% 单帧跳变保护，本轮没有改动跟踪参数。
- 点击要求拇指中指先分开 100ms，再接触 80ms；中指和拇指运动不影响食指黄点，接触处显示第二个黄色圆点，分开后才能再次点击。
- 合成点击使用独立 `.privateState` Core Graphics 事件源并强制清空修饰键，确保网页收到普通左键而不是 Command-click。
- 全屏骨架和 MediaPipe 校准窗口在有效食指指针上显示 22pt 黄色指尖点；Apple Vision 备用模式不发送鼠标事件。
- 竖拇指点赞识别与标记继续保留，但不执行真实点赞。
- 识别窗口显示实时 FPS 与推理耗时，30 FPS 性能不足时自动降到 24 FPS。
- 全屏骨架 HUD 保持点击穿透；实时状态固定底部居中，右侧三道杠单击收到右边缘左圆右方迷你条。迷你条只能上下移动，双击恢复默认帧。
- 双击展开反馈条可暂停/恢复识别；暂停停止摄像头、MediaPipe、Apple Vision 和系统事件，隐藏骨架，保留红点与“已暂停手势控制”。
- 主菜单新增右手/左手互斥选择，默认右手并持久保存；未选择手和未知左右手数据在动作入口被严格丢弃，切换时立即取消活动手势。
- 系统滚动改为 `.cghidEventTap` 全局注入，事件位置设为目标前台窗口中心，修复 Chromium 可能忽略 `postToPid` 滚轮事件的问题。
- App 改为正常 Dock 控制窗口并保留菜单栏入口，解决菜单栏项目被隐藏后启动即退出、退出后找不到入口的问题。
- 已安装 `/Applications/GestureControl.app`；诊断实测 MediaPipe GPU ready，并实时返回“左手 · 已识别手掌姿态”。

## 已验证

- `npm test`：32 项全部通过。
- `npm run typecheck`：通过。
- `swift test`：31 项 XCTest 全部通过，包括食指激活、定位、拇指展开过渡、拇指点击、单次消费、整掌不点击、分类容错、跳变保护及捏合优先级。
- `swift run GestureControlCoreChecks`：22 项全部通过。
- `swift build --target GestureControlApp`：通过。
- Release `.app`、Info.plist、camera entitlement、ad-hoc codesign：通过。
- v0.4.0 Gesture Recognizer 已在打包 App 中达到 MediaPipe GPU ready，摄像头、模型和 WKWebView 本机服务链路正常。
- 最终 `0.4.0`（build 5）已安装并启动于 `/Applications/GestureControl.app`，ad-hoc 签名和内置手势模型校验通过。
- `0.4.1`（build 6）为 ad-hoc 签名加入稳定 designated requirement；旧 GestureControl 辅助功能记录已单独重置，摄像头与辅助功能已由 App 实际读取为“已允许”。
- `0.5.0`（build 7）的 Swift 编译和 12 项 XCTest 通过；运行时窗口检查确认骨架与 `390×52` 状态条已分离，最终版已安装到 `/Applications/GestureControl.app`。
- `0.5.1`（build 8）已通过 Swift 编译、warnings-as-errors、12 项 XCTest 和 10 项核心检查，最终版已安装到 `/Applications/GestureControl.app`。
- 实机窗口检查确认：默认条 `390×52`，右边缘迷你条 `30×44`；纵向拖动实测 Y 位置变化 270pt 而 X 保持不变，双击恢复默认帧成功。
- 双击暂停实测为红色暂停状态、MediaPipe/摄像头/骨架窗口全部停止；再次双击后 MediaPipe GPU 恢复，摄像头与辅助功能仍为“已允许”。
- `0.6.0` 核心过滤单测已通过：右手模式拒绝左手，左手模式拒绝右手，未知左右手也被拒绝。
- 最终 `0.6.0`（build 9）已安装到 `/Applications/GestureControl.app`；界面实测右手/左手为互斥单选，切换与重启持久化正常，最终恢复为右手，摄像头和辅助功能仍显示“已允许”。
- `0.7.0`（build 10）已通过 18 项 XCTest、12 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.7.0` 已安装到 `/Applications/GestureControl.app`；界面检查确认摄像头/辅助功能均为“已允许”，MediaPipe GPU 正常就绪，默认等待右手，新动作说明已显示。
- `0.7.1`（build 11）已通过 19 项 XCTest、13 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.7.1` 已安装并启动；界面检查确认食指翻页/V 留空文案正确、权限仍为“已允许”，MediaPipe GPU 正常就绪并等待右手。
- `0.7.2`（build 12）已通过 22 项 XCTest、15 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.7.2` 已安装并启动；界面检查确认“握拳竖食指左右跨中线”文案正确、权限仍为“已允许”，MediaPipe GPU 正常就绪并等待右手。
- `0.7.3`（build 13）已通过 20 项 XCTest、14 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.7.3` 已安装并启动；界面检查确认张开手掌翻页、食指/V 留空文案正确，摄像头与辅助功能均为“已允许”，MediaPipe GPU 以 26 FPS / 14.0ms 正常就绪并等待右手。
- `0.8.0`（build 14）已通过 28 项 XCTest、20 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.8.0` 已安装并启动；界面确认食指指针测试默认关闭、摄像头与辅助功能均为“已允许”，MediaPipe GPU 以约 25 FPS / 16.0ms 正常就绪并等待右手。
- `0.8.1`（build 15）已通过 31 项 XCTest、22 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.8.1` 已安装并启动；界面确认新拇指点击说明正确，摄像头与辅助功能仍为“已允许”，MediaPipe GPU 正常就绪并等待右手。
- `0.8.2`（build 16）已通过 31 项 XCTest、22 项核心检查、32 项 Web 回归、TypeScript typecheck、warnings-as-errors、Release 构建和严格签名验证。
- 最终 `0.8.2` 已安装并启动；界面确认拇指中指轻捏说明正确，摄像头与辅助功能均为“已允许”，MediaPipe GPU 以约 26 FPS / 14.0ms 正常就绪并等待右手。

## 尚未验证

- 尚需用户主观验收迷你条造型、拖动手感与双击节奏。
- 尚需用户用真实张开手掌验收双向翻页灵敏度及误触率。
- 尚需用户在 YouTube 实测食指鼠标定位、双黄色点、拇指中指轻捏点击手感，以及链接是否始终在当前页打开。
- 60 秒真实手掌下的平均推理耗时、有效 FPS 与两分钟静止误触率尚未记录。
- 当前没有 Developer ID 正式签名、notarization 或自动更新。
- 尚需实机确认物理右手/左手与菜单标签一致，并验证未选择手不会显示骨架或触发动作。

## 下一步

1. 在 Chrome 打开 YouTube 首页，主动开启“食指指针（测试）”，验证黄色点、鼠标和悬停视频一致。
2. 食指停稳后先分开拇指和中指，看到待点击提示再轻捏，验证第二黄点和单次当前页点击；保持接触不得连点。
3. 验证普通张掌不点击且仍能左右翻页，严格 OK 仍能滚动和返回/前进。
4. 在其他三个浏览器和非浏览器回归白名单、单手选择、点赞、暂停和性能。

## 重要边界

- 食指鼠标仅为默认关闭的浏览器测试功能；不扩展为全系统 Air Mouse、拖拽或多显示器映射。
- 不申请屏幕录制或输入监控权限。
- 不推送 GitHub、申请证书、notarize 或发布 App Store，除非用户明确要求。
- 浏览器插件回滚点为本地 tag `v1.0.1`；macOS 重要稳定回滚点为 `macos-v0.3.0`。
