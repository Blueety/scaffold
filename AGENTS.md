# Agent Instructions — 脚手架仓库

> 这个仓库**不是**某个产品项目，它是「个人项目脚手架」的源码：`templates/` 是模板，`init.sh` / `init.ps1` 把模板复制成 `my-project-name/` 并替换占位符。
>
> 生成出来的项目**自己有一份 `AGENTS.md`**（`templates/AGENTS.md`），规则完全不同（任务分级、闸门、审查）。别把那一套当成本仓库的规则。
>
> 动这个仓库之前先读 `README.md`（用法 + 生成物目录树）和 `WORKFLOW.md`（生成项目的工作流程）。

## 仓库地图

- `templates/` —— 生成项目的**镜像**：它长什么样，生成出来的项目就长什么样（差别只有空的 `src/` 和 `.git`）。**没有**「脚本里另有一套映射」，读 `templates/` 就等于读生成结果。
- `init.sh` / `init.ps1` —— 两个平台各一份生成器，**必须等价**。
- `scripts/check-tree.ps1` —— 本仓库自己的自检器（**不随项目分发**）。校验 README 树 == `templates/` == 两个脚本的真实产物，且逐字节相同。
- `scripts/scaffold-update.sh` —— 把脚手架更新推到**已生成的项目**里：逐文件三方合并（项目现状 / 生成时的旧模板 / 当前模板），保留本地改动，冲突写标记并返回 1（**不随项目分发**；bash 4+）。配套 `scaffold-update.ps1`（Windows 入口，纯 ASCII）与 `fixtures/update-test.sh`（54 项验收）。`fixtures/gate-test.sh` 是闸门检查器的 71 项验收（规模底线含跨提交累计、空索引豁免与模板目录排除 / 模块表一格多路径 / 文档断链、gitignore、产物与后缀解析 / ADR 互链 / 决策锚点 / seam 措辞一致性 / 目标必填 / 纯重命名豁免 / 拍平归档 / journal 去向）。
- `.githooks/pre-commit` —— 提交前自动跑上面那个自检器（全量）。
- `README.md` —— 用法，以及**唯一一份**生成物目录树。
- `INTRO.md` —— 给第一次接触的人看的介绍：解决什么问题、一个任务走一遍、四道闸门、关键取舍、不适用场景。
- `WORKFLOW.md` —— 生成项目的完整工作流程（写给用户看，不是本仓库的贡献指南）。
- `web-chat-templates/` —— Phase 1 网页对话用的提示词模板（不随项目分发）。

## 硬约束

改错这几条会**静默**毁掉生成物——检查器能挡住一部分，挡不住的要靠自己：

1. **`templates/` 必须是纯 LF。** 一个 CR 就会让 `init.sh`（走 sed，MSYS 会把 CRLF 折成 LF）与 `init.ps1`（保字节）产出**不同**的项目；生成的钩子在 Linux / macOS 上还会 `bad interpreter: No such file or directory`。检查器会拦。
2. **`init.sh` 与 `init.ps1` 必须等价。** 项目名的接受 / 拒绝集必须**完全一致**（含控制字符、不可见 Unicode 空白、Windows 保留设备名、尾随点）；同一份模板经两个脚本必须产出**逐字节相同**的文件。改了一边的校验规则或替换逻辑，另一边**必须同步**。
3. **`README.md` 里那棵树是唯一真源。** `templates/` 和两个脚本的产物都向它对齐。不要在别处再画一棵树，也不要写死文件数 / 目录数——它们会漂。`WORKFLOW.md` 只留指针。
4. **`templates/` 里不放「只有本机才有」的东西。** 它是生成物的镜像，生成物要能 clone 到 Linux / macOS 上直接跑。

## 改完必须跑

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1
```

提交时 `.githooks/pre-commit` 会自动跑同一份（全量，约 20 秒）。被拦下就修，**不要**习惯性 `git commit --no-verify`。

CI 上（`.github/workflows/check.yml`）跑同一组不变量，外加两个 fixture；macOS 那组用系统 bash 3.2 生成并跑闸门——**生成的脚本不许用 bash 4 语法**，这条只有真在 3.2 上跑才算数。

`-SkipEndToEnd` 只跑纯文件系统对比（毫秒级），**提交闸门不用它**——逐字节比对才是这个仓库的核心不变量。`-BashPath <path>` 在 Git Bash 不在常见位置时用。

## 别做的事

- 不手写可推导的内容（目录树、文件数、目录数）——留一份源，其余引用它。
- 不「顺手」改 `templates/` 里的规则文件（skill / 流程 / 角色提示词）：那是所有未来项目的流程，属于设计决策，先说清楚再动。
- 不把 `scripts/check-tree.ps1` 塞进 `templates/`：它是本仓库的工具，不随项目走。生成项目里的闸门是 `templates/scripts/check-gates.sh` + `templates/.githooks/pre-commit`。
- 不给 `templates/` 加 BOM、不加 CRLF、不改编码。

## clone 到新机器后

`core.hooksPath` 存在 `.git/config` 里，**不随 clone 走**。跑一次，否则提交闸门根本不会执行：

```bash
git config core.hooksPath .githooks
```
