# 个人项目脚手架

一条命令生成项目骨架，骨架里带**一套让 AI 按流程干活、并且能被机器检查的规则**。

![闸门演示：提交被拦下，补上内容后通过](assets/demo.svg)

**生成出来的是什么**：30 个文件——23 份 markdown（一份规范、一份定档规则、两个角色提示词、七个流程 skill、五份任务模板、四份活文档、三份目录索引），外加检查器与钩子（`check-gates.sh` + `check-gates.awk` + 两个 POSIX sh 钩子）和三份配置。**不含语言、框架、依赖**——技术栈由你自己 `npm init` / `uv init`，骨架只管「AI 按什么流程干活」。

**它需要什么样的 agent**：能派**独立子 agent** 的工具（Claude Code、Codex CLI、任何能开子会话的编排器）——整套设计的核心是「写计划的人和实施的人不共享上下文」。没有这个原语的编辑器（比如 Cursor 的对话式 Composer）也能用其余部分，但规划 / 实施分离会退化成同一个上下文里自演，那一条只能靠人自觉。

> **English (short)** — One command scaffolds a project skeleton that encodes an **AI workflow with
> executable checks**: task state in git, a gate checker on `pre-commit`, and planning / implementation /
> review in *separate* agent contexts. Every core rule has either a machine check or an explicit
> "human judgment" label. Windows (PowerShell 5.1+) / Linux / macOS, stock bash 3.2, no runtime deps.
> Docs are Chinese; start with [`INTRO.md`](INTRO.md).
>
> ```bash
> bash init.sh my-project-name      # Windows: .\init.ps1 my-project-name
> ```

## 它解决什么问题

和 AI 一起写代码，崩掉的通常不是模型不够强，而是四件事：

1. **需求在聊天记录里蒸发。** 昨天聊透的结论，今天开个新会话就没了。这里的任务目录把 `prd.md` / `plan.md` / `journal.md` 存在 git 里——读这三份就能接上，不用重讲一遍。
2. **说「已完成」，其实没跑过。** 所以每个流程有**退出门槛**（下面叫「闸门」）而不是步骤清单：修 bug 得先有一条能对**这个** bug 变红的命令；提交前要贴真实输出，不接受「应该可以」。
3. **计划写一套、实现另一套。** 计划批准后，实施者是一个只拿到 `prd.md` + `plan.md` 的新上下文，没参与过讨论；大改动的审查再换第三个。同一个上下文里，实施者分不清「计划写的」和「我记得当时为什么这么定」。
4. **同一个坑踩第二遍。** 坑进 `docs/pitfalls.md`，决策进 `docs/adr/`，任务里的每条提醒必须写明去向——因为归档之后没人会再翻那份 journal。

**一句话：规则写成能跑的命令，不写成提醒。** 核心流程里每条规矩，要么有机器能验的检查，要么被明确标成「只能靠人看」；两者之间不留空白。判断哪些值得做成检查，就是这份脚手架的主要工作。

> 它不适合一次性的脚本或几十行的实验：流程比活本身大。视觉类项目可以进——截图像素基线也是客观信号。

**想先看全貌再动手的，读 [`INTRO.md`](INTRO.md)**：一个任务走一遍的流程图、四道闸门、六条关键取舍。本文件讲怎么用和为什么这么设计。

## 需要什么

| | 要求 |
|---|---|
| 公共 | `git`（两个脚本都会 `git init` 并写 `.git/config`） |
| Windows | PowerShell 5.1 或 pwsh |
| Linux / macOS / WSL | `bash`（3.2 即可）、`awk`、`sed`——**尚未在真机上验证**，见下方「CI」一节 |

生成的**项目**不需要 Node / Python / 任何运行时——闸门是 bash + awk。

更新器的额外要求（bash 4）写在 [`UPDATE.md`](UPDATE.md) 里——那是另一件事。

## 用法

### Windows (PowerShell)

```powershell
.\init.ps1 my-project-name
```

默认执行策略（`Restricted`）下这条会报「在此系统上禁止运行脚本」。不改策略的话，用这一行代替：

```powershell
powershell -ExecutionPolicy Bypass -File .\init.ps1 my-project-name
```

### Linux / macOS / WSL (Bash)

```bash
bash init.sh my-project-name
```

脚本会在当前目录下创建 `my-project-name/` 并生成完整目录结构。

项目名允许字母、数字、`.`、`_`、`-` 和非 ASCII 字符（中文等）；不能是 `.` / `..` / `.git`（不分大小写），不能以 `-` 开头或以 `.` 结尾，不能是 Windows 保留设备名（`CON` / `PRN` / `AUX` / `NUL` / `COM1`–`COM9` / `LPT1`–`LPT9`），也不能含空格、引号、路径分隔符或 shell 元字符。两个脚本的接受集相同。

## 生成的目录结构

```
my-project-name/
├── AGENTS.md              # 项目规范（含任务分级和闸门的指针）
├── CONTEXT.md             # 领域词表（空壳，首次术语定案时填）
├── README.md              # 项目说明
├── .gitignore             # Git 忽略规则
├── .gitattributes         # 锁 LF（脚本与钩子在 Linux/macOS 上必须无 CRLF）
├── .scaffold-kinds        # 模板文件分类：mechanism 本地一改就取模板 / content 按内容合并
├── src/                   # 源代码目录（空）
├── scripts/
│   ├── check-gates.sh     # 闸门检查器（plan / prd / journal / 切片 / review / 架构 / [DEBUG- 残留）
│   └── check-gates.awk    # 上面那个的判定逻辑（每个文件一次进程，见文件头）
├── .githooks/
│   ├── pre-commit         # 提交前调 check-gates.sh（并校验闸门文件本身没被偷偷改过）
│   ├── pre-merge-commit   # 合并提交走同一条检查（git 合并时不调用 pre-commit）
│   └── pre-push           # 推送前跑一次全量自查（cherry-pick / rebase / am 没有钩子入口）
├── docs/
│   ├── architecture.md    # 架构说明（活文档：模块/接口/数据模型/数据流）
│   ├── commands.md        # 命令说明
│   ├── pitfalls.md        # 易错点记录
│   ├── adr/
│   │   └── README.md      # 决策记录规范（为什么这么做）
│   └── agents/
│       ├── 架构师.md       # 架构师角色提示词
│       ├── 执行者.md       # 执行者角色提示词
│       └── 任务分级.md      # 档位判定：6 条信号 + 4 条升级规则
├── tasks/
│   ├── README.md          # 任务目录说明
│   └── _template/         # 任务模板
│       ├── prd.md
│       ├── plan.md
│       ├── journal.md
│       ├── review.md      # 审查裁决单（T2 / T3 必填）
│       └── slice.md       # 大需求拆切片时用（也承载决策条目）
└── skills/
    ├── bug-fix/
    │   └── SKILL.md       # Bug 修复流程（含闸门 A / B）
    ├── pre-review/
    │   └── SKILL.md       # 提交前双轴审查
    ├── receiving-review/
    │   └── SKILL.md       # 处理审查意见（防表演式附和 / 盲从）
    ├── self-audit/
    │   └── SKILL.md       # 一致性走查（活文档 vs 现实）
    ├── refactor/
    │   └── SKILL.md       # 重构：先造行为安全网，再改结构
    ├── research/
    │   └── SKILL.md       # 外查一手资料（后台子 agent + 带引用的 md）
    └── tdd/
        └── SKILL.md       # 测试驱动（seam 先约定）
```

## 生成后要做的事

1. **确认模块根**：闸门默认只在 `src/` 下数模块和文件。如果技术栈把代码放在别处（`app/`、`web/`、`cmd/`），现在就说清楚——用 `MODULE_ROOT=app` 跑闸门，或改 `scripts/check-gates.sh` 里那一行默认值。不改的话，模块表比对和规模底线会空转（闸门会打一条 `[!]` 提示，但**不会拦**），你看到的是一片绿。
2. **初始化技术栈**：在项目目录里运行 `npm init`、`create-next-app`、`uv init` 等。
3. **让 Agent 填写规范**：配置文件就位后，让本地 Agent 读配置文件并填写 AGENTS.md、CONTEXT.md 和 docs/（含把 Task Handoff 里的决策落成 `docs/adr/0001-*.md`）。
4. **提交**：`git add . && git commit -m "init: 项目脚手架 + 技术栈"`

生成脚本已经做过的事（不用重来）：`git init`、`core.quotepath=false`（否则中文路径会被转义成八进制）、把 `.githooks/` 挂成钩子目录（`pre-commit` / `pre-merge-commit` / `pre-push`）；生成的钩子在 `git commit` 与 `git merge` 时跑闸门，`git push` 前再补一次全量自查。

`core.hooksPath` 写在 `.git/config` 里，**不会随 clone 走**。clone 到别的机器后要跑一次：

```bash
git config core.hooksPath .githooks
```

完整流程见 [WORKFLOW.md](WORKFLOW.md)。

## 更新已生成的项目

脚手架改了之后，已生成的项目**不用重新生成**：

```bash
bash scripts/scaffold-update.sh ../my-project-name           # 预览，不写盘
bash scripts/scaffold-update.sh ../my-project-name --write   # 写盘（脚本不提交）
```

逐文件三方合并（项目现状 × 生成时的旧模板 × 当前模板）：没动过的升级；`mechanism` 类（钩子、闸门脚本、角色提示词、模板四件）本地一改就取模板版并把本地版留在现场；其余本地改过的、模板没动就保留，两边都改走 `git merge-file`。只碰 `templates/` 里出现过的路径，`src/` 与 `tasks/<任务>/` 一概不动。

基线选择、冲突现场、`--keep-local` / `--union` 裁决、全部开关、Windows 包装器 → **[`UPDATE.md`](UPDATE.md)**。

---

## 自检

> 这一节和下面的「CI」是给**改这个脚手架的人**的。只想用的话，读到上一节就够了。
>
> 动手之前先读 [`AGENTS.md`](AGENTS.md)：`templates/` 的 LF 约束、两个 init 脚本必须等价、README 树是唯一真源。生成出来的项目另有一份自己的 `AGENTS.md`，规则不同。


改了 `templates/` 或那两个脚本之后，跑一遍：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1
```

它校验四样东西一致：`README.md` 里那棵树、`templates/` 的实际内容、`init.sh` / `init.ps1` 实际生成的结果，以及**两个脚本产出的文件逐字节相同**（并断言每个产物与其模板「把占位符换成项目名」后逐字节相同）。同时断言"全仓库只有一棵树"——`WORKFLOW.md` 只留指针，所以模板变更只需改一处。

只比文件名集合是不够的：一个多写的换行、一次编码损坏、只有一边做了的替换，都能让两个脚本产出不同的项目而文件名完全一致。这类差异靠 SHA256 逐文件比。

### 改了什么就跑什么

| 改的东西 | 跑什么 |
|---|---|
| `templates/` 或 `init.*` | `check-tree.ps1`（上面那个，约 10–20 秒） |
| 项目名校验（`init.sh` / `init.ps1`） | `bash scripts/fixtures/name-test.sh` —— 约 1 分钟：同一张名字表分别喂两个脚本，接受 / 拒绝必须一致；没有 PowerShell 的机器会跳过 |
| 闸门（`scripts/check-gates.*`） | `bash scripts/fixtures/gate-test.sh` —— 约 20 分钟：闸门各项判据的验收（判据清单见 `bash scripts/check-gates.sh --help`，项数看收尾输出）。改了 `check-gates.{sh,awk}` 必须跑 |
| 更新器（`scripts/scaffold-update.sh`） | `bash scripts/fixtures/update-test.sh` —— 约 2–4 分钟：冲突现场、脏树、裁决、并集、基线阈值、adopt、闸门计数、机制文件、MANIFEST / JSON、`--quiet` |

### 自动跑

本仓库的 `.githooks/pre-commit` 会在提交前跑同一份**全量**检查（约 20 秒），不一致就拦下提交——这条不变量不该只靠人记得跑。被拦下就修，别习惯性 `git commit --no-verify`。

`core.hooksPath` 存在 `.git/config` 里，**不随 clone 走**。clone 到新机器后要跑一次，否则钩子根本不执行：

```bash
git config core.hooksPath .githooks
```

非 Windows 平台（Linux / macOS）上钩子**一律跳过**——`uname` 判断在找 PowerShell 之前，所以装了 pwsh 也不跑（本仓库暂无 POSIX 版检查器，那半边本该由 CI 覆盖——而 CI 至今没跑过，见下）。Windows 上找不到 PowerShell 时同样跳过并提示。

- `-SkipEndToEnd`：只跑前半段（纯文件系统对比，毫秒级）——给手动排查用，提交闸门不用它
- `-BashPath <path>`：Git Bash 不在常见位置时手动指定

### CI（`.github/workflows/check.yml`）——写好待跑

本地钩子只在你自己的机器、你自己的提交上生效。外部 PR 跑不了 `check-tree.ps1`——**脚本第一道门就是平台判断，非 Windows 直接 `exit 3`**（它依赖 `init.ps1` 与 Git for Windows 的路径语义），所以同一组不变量在 CI 上再跑一遍：

| 任务 | 跑什么 | 为什么是这个平台 |
|---|---|---|
| `windows` | `check-tree.ps1` 全量 + 三个 fixture | 唯一能做「README 树 vs 两脚本产物」全量比对的平台 |
| `linux` | `templates/` vs `init.sh` 产物逐字节比对 + 三个 fixture（项目名一致性那项会跳过） | 覆盖 GNU 工具链；比对前按项目名展开占位符 |
| `macos` | 用系统 `/bin/bash`（3.2）生成项目，再用系统 `/bin/sh` 跑闸门 | 证明生成的项目不依赖 bash 4 —— 这条约束只有真在 3.2 上跑才算数。macOS 的 `/bin/sh` 是 bash 3.2 的 POSIX 模式；Linux 的 `/bin/sh` 是 dash，跑不了（会死在数组语法），Linux 那边按 README 要求用 `bash` |

三组都是红的就说明不变量破了；红了别合，和本地钩子一个标准。

> **这三组 job 一次都没跑过。** 仓库还没推到 GitHub，没有 remote，所以上面的 macOS / Linux 支持目前只有**代码层面的保证**——生成出来的脚本不用 bash 4 语法（`local -A`、`mapfile`、`${x,,}`、`local -n`、`&>>`）、`mktemp` 一律带模板、不依赖 BSD 不认的长选项、不用 `sed -i`（写到临时文件再读回）。这些都是靠人工逐处避开写成的，**没有实际运行证据**。
>
> 结论：在 CI 第一次跑通之前，把 macOS / Linux 当成「按约定写成这样」，不要当成「已验证」。Windows 那半边不受影响——那是本地钩子每次提交都在跑的。


## 设计原则

- 模板只写 AI 推不出来的东西。其余写成指针，指向 `docs/`
- 规则必须可检查，不写空话
- **每个流程都有退出门槛**，不是只有步骤清单。见 `docs/agents/任务分级.md`、`skills/bug-fix/SKILL.md` 的闸门 A / B
- 任务有状态（prd/plan/journal），新会话能接续
- 经验沉淀到 `docs/pitfalls.md`，决策沉淀到 `docs/adr/`，术语沉淀到 `CONTEXT.md`——都不留在聊天记录里
- 角色提示词进仓库（`docs/agents/`），不靠每次手动粘贴
- 验证是默认步骤，不是可选项

## 进一步阅读

| 想知道什么 | 看哪里 |
|---|---|
| 它解决什么问题、一个任务怎么走、为什么不这么设计不行 | [`INTRO.md`](INTRO.md)：**第一次接触从这里开始** |
| 一个任务从需求到提交的逐步操作（Phase 1–4） | [`WORKFLOW.md`](WORKFLOW.md) |
| 更新已生成的项目：基线、冲突、裁决、全部开关 | [`UPDATE.md`](UPDATE.md) |
| 改这个仓库本身的约束与禁区 | [`AGENTS.md`](AGENTS.md) |
| 生成后的项目里怎么定档位、闸门查什么、任务目录怎么用 | 生成项目自己的 `AGENTS.md` / `docs/agents/任务分级.md` / `tasks/README.md` |
| 在网页 AI（GPT / Claude / Gemini）里怎么把讨论整理成任务，再交接给本地 agent | [`web-chat-templates/`](web-chat-templates/README.md)：六份提示词模板，起点是 `project-kickoff.md`，收尾是 `task-handoff.md` |


## 许可

MIT，见 [`LICENSE`](LICENSE)。生成出来的项目是你的，不带任何署名要求。

