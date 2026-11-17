# Agent Instructions — 脚手架仓库

> 这个仓库**不是**某个产品项目，它是「Vibecoding 工作流脚手架」（`scaffold`）的源码：`templates/` 是模板，`init.sh` / `init.ps1` 把模板复制成 `my-project-name/` 并替换占位符。
>
> 生成出来的项目**自己有一份 `AGENTS.md`**（`templates/AGENTS.md`），规则完全不同（任务分级、闸门、审查）。别把那一套当成本仓库的规则。
>
> 动这个仓库之前先读 `CONTRIBUTING.md`（怎么改、跑什么、生成物目录树）和 `WORKFLOW.md`（生成项目的工作流程）。

## 仓库地图

- `templates/` —— 生成项目的**镜像**：它长什么样，生成出来的项目就长什么样（差别只有空的 `src/` 和 `.git`）。**没有**「脚本里另有一套映射」，读 `templates/` 就等于读生成结果。
- `init.sh` / `init.ps1` —— 两个平台各一份生成器，**必须等价**。
- `scripts/check-tree.ps1` —— 本仓库自己的自检器（**不随项目分发**）。校验 `CONTRIBUTING.md` 里的树 == `templates/` == 两个脚本的真实产物，且逐字节相同。
- `scripts/scaffold-update.sh` —— 把脚手架更新推到**已生成的项目**里：逐文件三方合并（项目现状 / 生成时的旧模板 / 当前模板），保留本地改动，冲突写标记并返回 1（**不随项目分发**；bash 4+）。配套 `scaffold-update.ps1`（Windows 入口，纯 ASCII）与 `fixtures/update-test.sh`（更新器验收）、`fixtures/name-test.sh`（两个 init 脚本的项目名接受集必须一致）。`fixtures/gate-test.sh` 是闸门检查器的验收（对抗性变体、review 字段契约、计划范围归属、环境提示、gate 头块的语法与取值、去向右值与旧箭头废除、prd 档位可选、行尾 CR 不改变结论、规模底线含跨提交累计、空索引豁免与模板目录排除 / 模块表一格多路径 / 文档断链、gitignore、产物与后缀解析 / ADR 互链 / 决策锚点 / seam 措辞一致性 / 目标必填 / 纯重命名豁免 / 拍平归档 / journal 去向）。
- `.githooks/pre-commit` —— 提交前自动跑上面那个自检器（全量）。
- `README.md` —— 面向使用者：三段话、一条命令、跟 Agent 说什么、三件容易踩的事。维护细节不在这里。
- `INTRO.md` —— 给第一次接触的人看的介绍：解决什么问题、四段流程全景图、一个任务走一遍、四道闸门、关键取舍、不适用场景。
- `WORKFLOW.md` —— 生成项目的完整工作流程（写给用户看，不是本仓库的贡献指南）。
- `UPDATE.md` —— 更新器的手册：基线选择、冲突现场、三类文件、裁决、全部开关。README 里只留两条命令和一行指针。
- `CONTRIBUTING.md` —— 面向改这个仓库的人：硬约束、改完跑什么、CI 三组 job，以及**唯一一份**生成物目录树。
- `web-chat-templates/` —— Phase 1 网页对话用的提示词模板（不随项目分发）。
- `assets/` —— 文档里的图（`demo.svg` 是真实终端的输出渲染，不是示意图；`flow.svg` 是 `INTRO.md` 的四段流程示意图，改流程时两处一起改）。

## 硬约束

改错这几条会**静默**毁掉生成物——检查器能挡住一部分，挡不住的要靠自己：

1. **`templates/` 必须是纯 LF。** 一个 CR 就会让 `init.sh`（走 sed，MSYS 会把 CRLF 折成 LF）与 `init.ps1`（保字节）产出**不同**的项目；生成的钩子在 Linux / macOS 上还会 `bad interpreter: No such file or directory`。检查器会拦。
2. **`init.sh` 与 `init.ps1` 必须等价。** 项目名的接受 / 拒绝集必须**完全一致**（含控制字符、不可见 Unicode 空白、Windows 保留设备名、尾随点）；同一份模板经两个脚本必须产出**逐字节相同**的文件。改了一边的校验规则或替换逻辑，另一边**必须同步**。
3. **`CONTRIBUTING.md` 里那棵树是唯一真源。** `templates/` 和两个脚本的产物都向它对齐。不要在别处再画一棵树，也不要写死文件数 / 目录数——它们会漂。`WORKFLOW.md` 只留指针。
4. **`templates/` 里不放「只有本机才有」的东西。** 它是生成物的镜像，生成物要能 clone 到 Linux / macOS 上直接跑。

## 改完必须跑

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1
```

提交时 `.githooks/pre-commit` 会自动跑同一份（全量，约 20 秒）。被拦下就修，**不要**习惯性 `git commit --no-verify`。

CI 上（`.github/workflows/check.yml`）跑同一组不变量，外加三个 fixture（项目名一致性 / 闸门 / 更新器）；macOS 那组用系统 bash 3.2 生成并跑闸门——**生成的脚本不许用 bash 4 语法，也不许用进程替换**（`< <(cmd)` 在 bash 3.2 的 POSIX 模式下是解析错误，整个文件一行都跑不到；要按行读命令输出用 `| feed`，见 `check-gates.sh` 顶部）。第一次 push 已抓出这两个真缺陷；之后每次 push 都以 Actions 结果为准。

`-SkipEndToEnd` 只跑纯文件系统对比（毫秒级），**提交闸门不用它**——逐字节比对才是这个仓库的核心不变量。`-BashPath <path>` 在 Git Bash 不在常见位置时用。

## 别做的事

- 不手写可推导的内容（目录树、文件数、目录数、**fixture 的断言项数**）——留一份源，其余引用它。项数的唯一出处是 fixture 自己的收尾输出（`PASS n / FAIL m`）；写进文档就会每加一条断言漂一次，闸门 `check_doc_counts` 会拦。
- 不「顺手」改 `templates/` 里的规则文件（skill / 流程 / 角色提示词）：那是所有未来项目的流程，属于设计决策，先说清楚再动。
- 不把 `scripts/check-tree.ps1` 塞进 `templates/`：它是本仓库的工具，不随项目走。生成项目里的闸门是 `templates/scripts/check-gates.sh` + `templates/.githooks/pre-commit` + `templates/.githooks/pre-merge-commit` + `templates/.githooks/pre-push`。
- 不给 `templates/` 加 BOM、不加 CRLF、不改编码。

## clone 到新机器后

`core.hooksPath` 存在 `.git/config` 里，**不随 clone 走**。跑一次，否则提交闸门根本不会执行：

```bash
git config core.hooksPath .githooks
```
