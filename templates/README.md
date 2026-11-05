# {{PROJECT_NAME}}

> 一句话说明这个项目做什么。

## 技术栈

<!-- 「难换的」六项就算结论是「先不用」也写出来——那是决策，不是遗漏。
     带锁定成本的选择（数据库、认证、部署）另按 ADR 三条准入进 docs/adr/。 -->

- 数据库:
- 查询层:
- 认证与授权:
- 文件与对象存储:
- 缓存:
- 队列或后台任务:
- 语言 / 框架:
- 包管理:
- 测试:
- 部署:

## 快速开始

```bash
# 安装
<install 命令>

# 开发
<dev 命令>

# 测试
<test 命令>

# 构建
<build 命令>
```

## 项目结构

```
src/                  源代码
AGENTS.md             项目规范（提交前钩子、编码规范、人必到节点）
CONTEXT.md            领域词表
docs/                 项目知识和规则
docs/adr/             决策记录（为什么这么做）
docs/agents/          角色提示词和流程细则
tasks/                任务目录
skills/               可复用流程
scripts/              闸门检查器（check-gates.sh + check-gates.awk）
.githooks/            提交前钩子（pre-commit）
```

## 开发约定

- 修改前先读 `docs/architecture.md`。
- 改动前先按 `docs/agents/任务分级.md` 声明档位。**T0 免检直接改，T1 的声明是通知**（发完就做，不等确认）；**T2 / T3 的计划要批准**。T1 起都必须把计划落到 `plan.md`，实施由执行者子 agent 按它做。
- 命名和描述用 `CONTEXT.md` 里的词。
- 修改行为前先跑测试。
- 修 bug 走 `skills/bug-fix/SKILL.md`：进根因假设前先有一条能对这个 bug 变红的命令（闸门 A）。
- 写测试走 `skills/tdd/SKILL.md`：先把 seam 写进 `plan.md`，再动手。
- 重构走 `skills/refactor/SKILL.md`：先造行为安全网，再改结构；行为一变就不是重构。
- 提交前走 `skills/pre-review/SKILL.md`：Standards / Spec 两轴分开报告。**T2 / T3 必须派独立子 agent 审**，产出 `tasks/<日期>-<简述>/review.md`；T1 自己审。提交时 `scripts/check-gates.sh --staged` 会拦 `[DEBUG-` 残留、`plan.md` / `journal.md` / 切片 / `review.md` 的字段、`architecture.md` 模块表与实际目录的偏差、**文档里指向不存在文件的相对路径**、**ADR 的取代关系只写一边**，以及**规模低报**（`src/` 下改 ≥ 4 个文件却没有 T2 / T3 的声明）。
- 收到审查意见走 `skills/receiving-review/SKILL.md`：每条发现落到「改 / 不改 + 理由 / 不接受 + 反证」，改完重跑验证。
- **长期项目定期走查**走 `skills/self-audit/SKILL.md`：逐条实跑 `docs/commands.md` 的命令、逐条对 `architecture.md` 的接口契约与数据模型、逐个 grep `CONTEXT.md` 的术语、逐条实跑 `docs/pitfalls.md` 的解决命令。触发：T3 任务结束 / 每 10 个任务 / 你说「查一下」。产出不一致清单，每条落到「改文档 / 改代码 / 删掉」。
- 提交时闸门自动跑（`core.hooksPath` 指向 `.githooks`）。手动全量：`sh scripts/check-gates.sh`（Windows 上别用 `bash`，它可能指向 WSL 的桩，会输出乱码并返回 1）；临时绕过：`git commit --no-verify`（别习惯性用）。
  clone 到新机器后要跑一次 `git config core.hooksPath .githooks`——这个设置在 `.git/config` 里，不随仓库走。
- 要查外部一手事实走 `skills/research/SKILL.md`：派后台子 agent，产出带引用的 `tasks/<日期>-<简述>/research/<slug>.md`；结论进 `CONTEXT.md` / `docs/adr/`，文件本身过期即删。
- 复杂任务先写 `tasks/<日期>-<简述>/prd.md`。
- 完成前运行 `docs/commands.md` 里的完整检查。
- 任务结束：可复用的规则写 `docs/pitfalls.md`，决策写 `docs/adr/`，日志写 `tasks/<日期>-<简述>/journal.md`。

## 相关文档

- [领域词表](CONTEXT.md)
- [架构说明](docs/architecture.md)
- [命令说明](docs/commands.md)
- [易错点](docs/pitfalls.md)
- [决策记录](docs/adr/README.md)
- [任务分级](docs/agents/任务分级.md)
- [架构师角色](docs/agents/架构师.md)
- [执行者角色](docs/agents/执行者.md)
