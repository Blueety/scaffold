# Agent Instructions — {{PROJECT_NAME}}

## Project Map

- `src/`: 源代码。
- `CONTEXT.md`: 领域词表。命名和描述一律用这里的词。
- `docs/`: 项目知识和规则。
- `docs/adr/`: 决策记录（为什么这么做）。
- `docs/agents/`: 角色提示词和流程细则。
- `tasks/`: 任务目录和交接记录。
- `skills/`: 可复用流程。

## Required Reading

- 任何任务开始前：`docs/agents/任务分级.md`，然后按格式声明档位。
- 修改前：`docs/architecture.md`。
- 改行为前：`docs/commands.md`。
- 写代码时：用 `CONTEXT.md` 的词；术语冲突当场指出并更新它。
- 复杂任务：当前 `tasks/<日期>-<简述>/` 下的 prd.md / plan.md / journal.md。
- 修 bug：`skills/bug-fix/SKILL.md`。
- 写测试：`skills/tdd/SKILL.md`。
- 重构：`skills/refactor/SKILL.md`（先造行为安全网；行为一变就不是重构）。
- 提交前审查：`skills/pre-review/SKILL.md`（T2 / T3 必须派**独立子 agent** 执行）。
- 处理审查意见：`skills/receiving-review/SKILL.md`（每条发现落到「改 / 不改+理由 / 不接受+反证」）。
- 外部一手事实挡住决策时：`skills/research/SKILL.md`（派后台子 agent，只认官方文档 / 源码 / 规范，落一份带引用的 md）。
- 长期项目的定期走查：`skills/self-audit/SKILL.md`（T3 任务结束 / 每 10 个任务 / 用户说「查一下」时做，逐条实跑活文档）。

## Commands

- Install: `<填写>`
- Test: `<填写>`
- Lint: `<填写>`
- Typecheck: `<填写>`
- Build: `<填写>`
- Dev: `<填写>`

## 编码规范

<!-- Standards 轴（skills/pre-review/SKILL.md）的「硬违规」只能引用写在这里的东西。
     这一节留空，审查就只剩坏味道（判断题），报不出硬违规。
     填这个仓库实际的约定，不要抄通用建议。 -->

- **命名**：`<文件 / 组件 / 函数 / 变量 / 常量 各用什么形式>`
- **目录与文件组织**：`<新文件放哪、什么算一个模块>`
- **错误处理**：`<抛还是返回、错误类型怎么定义、日志怎么打>`
- **输入校验**：`<哪些输入必须在服务端再校验一次——前端送来的东西一律不信任>`
- **密钥**：`<哪些密钥绝不能进客户端代码、绝不能提交>`
- **依赖**：`<能不能加新依赖、加了要走什么流程>`
- **测试**：`<放哪、怎么命名、什么算好测试>`
- **禁止**：`<这个仓库明确不要的做法>`

<!-- 接口层面的约定（URL 命名 / HTTP 方法 / 状态码 / 错误响应结构 / 版本 / 分页）
     写在 docs/architecture.md 的「接口契约 → 横切约定」，不在这里重复。 -->

## Working Rules

- 先只读分析，再动手。不要把分析和实现混在一轮里。
- 在只读分析末尾声明档位（一行）。**T0 / T1 是通知**——发完继续做，不等人回；**T2 / T3 的计划等你批准**（见 `docs/agents/任务分级.md` 的「人检查点与独立审查」），批准即授权这个规模，不再单独确认档位。
- 计划保存到 `tasks/<日期>-<简述>/plan.md`（日期用当天 `YYYY-MM-DD`，简述用简短英文，如 `2026-08-09-todo-title-search/plan.md`）。
  计划包含：目标、涉及文件、实施步骤、验证命令、测试 seam、预估 diff 范围。**只有 T0 可以不落盘**；T1 / T2 / T3 都要落——实施由执行者子 agent 做，它只认 `plan.md`，对话里的计划传不过去。
- **派执行者子 agent 实施（T1 / T2 / T3）**：写计划的人不实施。由规划者派一个**全新的子 agent** 按 `docs/agents/执行者.md` 实施，输入只给 `prd.md` + `plan.md` + 规范文件（`AGENTS.md`、`docs/architecture.md`、`docs/commands.md`、`CONTEXT.md`、`docs/pitfalls.md`），**不给规划过程的对话**——给了，它继承规划时的结论，`plan.md` 就约束不住实施。子 agent 报的「已完成」由主线程重跑关键命令复核，不能直接采信。T0 免检：不写计划，也就没有可派的东西。
- 保持 diff 最小，不重构无关代码。
- 不引入新依赖，除非先说明理由并等待确认。
- 不修改 `.env`、生产配置、生成文件。
- **不可逆的外部动作一律先报告、等确认**，不管档位多低：部署到生产、花钱、删改数据、改权限与密钥、隐私数据的读写与对外传输、会改变第三方状态的对外请求、申请新账号或新服务。
- 需求不清楚时先问，不要猜。
- 每完成一个逻辑步骤后运行验证命令，不接受「应该可以」——必须实际运行。
- 如有失败，先解释原因再修复，不要绕过问题。
- 修 bug 时：进入根因假设前，必须有一条已经实跑过、能对这个 bug 变红的命令（`skills/bug-fix/SKILL.md` 闸门 A）。
- 写测试前：先把要测的 seam 写进 `plan.md` 的「## 测试 Seam」一节（T0 / T1 写完即继续；T2 / T3 随 plan 一次批准）。没写进 plan、或与 plan 不符的，停下来问。
- 调试日志统一加 `[DEBUG-xxxx]` 前缀，提交前 grep 清干净。
- 提交前闸门是**自动**的：`.githooks/pre-commit` 会跑 `scripts/check-gates.sh --staged`，检查 `[DEBUG-` 残留、`docs/architecture.md` 的模块表与实际目录是否对得上、`plan.md` 的档位/类型/闸门 A 字段、`journal.md` 的章节与验证结果、切片文件的字段、**T2 / T3 的 `review.md` 是否存在且填全**。被拦下就按提示补内容，**不要**用 `git commit --no-verify` 绕过。手动全量检查：`sh scripts/check-gates.sh`（Windows 上 `bash` 可能指向 WSL 的桩，改用 `sh`）。
- 动手前先确认钩子真的挂上了：`git config core.hooksPath` 要输出 `.githooks`。这个设置在 `.git/config` 里，**clone 之后不会跟着来**——丢了钩子就不跑，闸门静默失效，而且没有任何提示。是空的话跑一次 `git config core.hooksPath .githooks`。
- 提交前审查：T0 不审；T1 自己审；**T2 / T3 必须派一个全新的子 agent 审**（只给它 `prd.md`、`plan.md`、diff、相关规范，**不给它会话历史**），产出 `tasks/<日期>-<简述>/review.md`。轮次上限 2，超了升级给人。
- 收到审查意见后按 `skills/receiving-review/SKILL.md` 逐条处理：改 / 不改+理由 / 不接受+反证，**没有第四种**；不能静默跳过任何一条。
- 验证通过后，运行 `git diff` 检查改动范围。
- 任务结束后：可复用的规则追加到 `docs/pitfalls.md`；符合 ADR 三条准入条件的决策写进 `docs/adr/NNNN-slug.md`。
- 任务结束后：日志写进 `tasks/<日期>-<简述>/journal.md`，内容包括目标、主要提交的 SHA、改动文件清单、验证结果、遇到的问题、下次注意什么、涉及的 ADR 编号、下一步、结束状态。

## Done Means

- 验收标准已满足。
- **声称完成前的四件事**都做了，或清楚标注未运行（见 `skills/pre-review/SKILL.md` 的「声称完成前」）：跑过相关测试 / 手动走过关键路径 / 跑过 lint 与 typecheck / 要改的文档已改。
- `[DEBUG-` 无残留（提交时 `scripts/check-gates.sh` 会自动验）；**一次性脚本已删**（这一条机器验不了，靠自己看）。
- diff 已摘要。
- **T2 / T3**：`review.md` 已按 `skills/receiving-review/SKILL.md` 处理完——每条发现都有归类，没有一条被静默跳过，「审查者明确未判断的」已列出。
- 风险和后续工作已列出。
