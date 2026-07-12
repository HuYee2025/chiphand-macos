# AI 工作规则

这个项目按长期项目处理。核心原则：不要让 AI 记住项目；让项目文件记住项目。

## 新对话自动读取规则

只要新对话是在这个项目文件夹里打开，AI 必须主动先读下面文件，不需要用户重复提醒：

1. `AGENTS.md`
2. `docs/project-management.md`
3. `docs/production-blueprint.md`
4. `docs/dev-log/current-handoff.md`
5. `docs/tech-plan.md`
6. `docs/decision-log.md`
7. `docs/dev-log/archive/` 中最新的 1 个阶段总结
8. 当前阶段或岗位相关文件

不要一开始读完整旧聊天。旧聊天是过程，项目文件才是事实。

## 工作方式

- 默认按阶段推进：第 01 阶段、第 02 阶段、第 03 阶段。
- 岗位明确时，也可以按岗位推进，例如：编剧、开发、Bug 修复、美术资产、GitHub 发布。
- 岗位不好分时，不要硬分，继续按阶段推进。
- 完成任务后必须写回项目文件，不要只停留在聊天里。
- 技术/UI/部署规则写入 `docs/tech-plan.md`。
- 重要取舍、方向改变、反复讨论后的结论写入 `docs/decision-log.md`。
- 对话超过 60-90 分钟、阶段完成、切换岗位、文件改动较多、AI 开始重复或变慢时，必须更新 `docs/dev-log/current-handoff.md`。
- 进入下一阶段前，必须把当前阶段总结归档到 `docs/dev-log/archive/`。
- 新对话只读最新权威文件，然后继续推进。
- 不要擅自删除、移动或重写已有重要资料；必要时先保留原文件。

## 稳定接力优先

- 这个项目可以借鉴 Loop Engineering，但目的不是全自动运行，而是让多个新对话之间稳定传递项目信息。
- 只有边界清楚、可验证、可停止的任务，才适合设计成循环任务。
- 每个循环任务都必须写清楚：触发条件、读取文件、执行动作、质量门、停止条件、写回位置。
- 默认最多尝试 3 轮；连续失败、验证不通过、需求不清楚或涉及高风险操作时，停止并写入交接。
- 每轮结束都必须更新状态文件，不能只把过程留在聊天里。

## 对话转场

需要新开对话时，先做三件事：

1. 把当前阶段总结写入 `docs/dev-log/archive/`。
2. 更新 `docs/dev-log/current-handoff.md`。
3. 确认重要结果已经写回项目文件。

然后用下面的话开启新对话：

```text
你现在继续这个项目的第【阶段编号】阶段。
请先读 AGENTS.md、docs/project-management.md、docs/production-blueprint.md、docs/dev-log/current-handoff.md，
再读 docs/tech-plan.md、docs/decision-log.md、docs/dev-log/archive/ 里最新的 1 个阶段总结和当前任务相关文件。
不要读完整旧聊天，以项目文件为准。
请从 current-handoff.md 的“下一步建议”继续执行。
```

## 质量门

- 先识别项目已有命令，不硬跑不存在的命令。Node/前端项目优先查看 `package.json` 的 `scripts`。
- 涉及代码修改时，优先运行项目已有的 `build`、`test`、`lint`、`typecheck`。
- 涉及多语言文案时，运行项目已有的 `i18n:audit`、`translate:check` 或同类翻译检查。
- 涉及页面、游戏、视觉或交互时，打开本地 `dev`/`preview` 预览并检查真实效果。
- 如果没有现成命令，先在 `docs/tech-plan.md` 记录建议的验证方式，不要假装已经验证。

## 回复要求

- 默认中文，简单直接，先给结论。
- 少解释空话，多给结果和文件位置。
- 涉及代码、命令、英文名词时保留英文。
