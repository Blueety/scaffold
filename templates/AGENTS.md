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
- 提交前审查：`skills/pre-review/SKILL.md`。
- 外部一手事实挡住决策时：`skills/research/SKILL.md`（派后台子 agent，只认官方文档 / 源码 / 规范，落一份带引用的 md）。

## Commands

- Install: `<填写>`
- Test: `<填写>`
- Lint: `<填写>`
- Typecheck: `<填写>`
- Build: `<填写>`
- Dev: `<填写>`

## Working Rules

- 先只读分析，再动手。不要把分析和实现混在一轮里。
- 在只读分析末尾声明档位（一行），等确认后再实施。
- 计划保存到 `tasks/<日期>-<简述>/plan.md`（日期用当天 `YYYY-MM-DD`，简述用简短英文，如 `2026-08-09-todo-title-search/plan.md`）。
  计划包含：目标、涉及文件、实施步骤、验证命令、测试 seam、预估 diff 范围。
- 保持 diff 最小，不重构无关代码。
- 不引入新依赖，除非先说明理由并等待确认。
- 不修改 `.env`、生产配置、生成文件。
- 需求不清楚时先问，不要猜。
- 每完成一个逻辑步骤后运行验证命令，不接受「应该可以」——必须实际运行。
- 如有失败，先解释原因再修复，不要绕过问题。
- 修 bug 时：进入根因假设前，必须有一条已经实跑过、能对这个 bug 变红的命令（`skills/bug-fix/SKILL.md` 闸门 A）。
- 写测试前：先书面列出要测的 seam 并等待确认。
- 调试日志统一加 `[DEBUG-xxxx]` 前缀，提交前 grep 清干净。
- 提交前闸门是**自动**的：`.githooks/pre-commit` 会跑 `scripts/check-gates.sh --staged`，检查 `[DEBUG-` 残留、`plan.md` 的档位/类型/闸门 A 字段、`journal.md` 的章节与验证结果。被拦下就按提示补内容，**不要**用 `git commit --no-verify` 绕过。手动全量检查：`bash scripts/check-gates.sh`。
- 验证通过后，运行 `git diff` 检查改动范围。
- 任务结束后：可复用的规则追加到 `docs/pitfalls.md`；符合 ADR 三条准入条件的决策写进 `docs/adr/NNNN-slug.md`。
- 任务结束后：日志写进 `tasks/<日期>-<简述>/journal.md`，内容包括目标、改动文件清单、验证结果、遇到的问题、下次注意什么、涉及的 ADR 编号、下一步。

## Done Means

- 验收标准已满足。
- 相关测试 / checks 已运行，或清楚标注未运行。
- `[DEBUG-` 无残留，一次性脚本已删（提交时 `scripts/check-gates.sh` 会自动验一遍）。
- diff 已摘要。
- 风险和后续工作已列出。
