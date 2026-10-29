# 网页对话模板

在浏览器 AI 对话（GPT / Claude / Gemini）中使用这些模板，把讨论整理成结构化任务，再交给本地 Agent。

## 工作流程

```
1. 打开网页对话（GPT / Claude / Gemini）
2. 自由讨论你的想法；技术栈用 tech-stack-decision、前端设计用 frontend-design 逐个定下来
3. 准备好后，贴 Task Brief 提示词 → 拿到结构化输出（含 User Stories 和术语与决策）
4. 压缩成 Task Handoff —— 删讨论过程，留术语和决策
5. 复制到项目目录: tasks/<date>-<slug>/prd.md
6. 交给本地 Agent（Claude Code / Codex / OpenCode）执行
```

第 4 步的压缩规则值得单独强调：**讨论过程可以删，术语、被排除的方案、刻意反常规的地方、看不见的约束这四类不能删**。它们之后会写进项目的 `CONTEXT.md` 和 `docs/adr/`，删了就永久丢了。

## 模板

| 模板 | 什么时候用 |
|---|---|
| [project-kickoff.md](project-kickoff.md) | 第一次聊新项目：理清想法、需求、验收标准、边界、术语 |
| [tech-stack-decision.md](tech-stack-decision.md) | 讨论和确定技术栈 |
| [frontend-design.md](frontend-design.md) | 技术栈定下来后，讨论界面设计、视觉方向、组件库 |
| [approach-comparison.md](approach-comparison.md) | 比较不同实现方案 |
| [task-brief.md](task-brief.md) | 把讨论结果整理成结构化任务 |
| [task-handoff.md](task-handoff.md) | 压缩成交接卡，交给本地 Agent |

## 在网页对话中使用的提示词

讨论完后，在 GPT / Claude / Gemini 中贴这段话：

```
我接下来要把这个需求交给本地 coding agent 执行。
请不要写代码。
请把我们的讨论整理成 Task Brief，重点写清楚：
目标、用户场景、范围、不做什么、上下文入口、约束、验收标准、风险。
另外单独写两段：
1. User Stories：长的编号列表，覆盖这个功能的各个方面
2. 术语与决策：术语表、被排除的方案、刻意反常规的地方、看不见的约束
输出要适合直接保存为 prd.md。
```

拿到 Task Brief 后，压缩成 Task Handoff，再交给本地 Agent。
