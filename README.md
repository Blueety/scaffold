# 个人项目脚手架

一键生成 Vibe Coding 开发系统所需的目录结构和规范文件。

> 改这个仓库之前先读 [`AGENTS.md`](AGENTS.md)：`templates/` 的 LF 约束、两个 init 脚本必须等价、README 树是唯一真源。生成出来的项目另有一份自己的 `AGENTS.md`，规则不同。

## 用法

### Windows (PowerShell)

```powershell
.\init.ps1 my-project-name
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
├── src/                   # 源代码目录（空）
├── scripts/
│   ├── check-gates.sh     # 闸门检查器（plan / prd / journal / 切片 / review / 架构 / [DEBUG- 残留）
│   └── check-gates.awk    # 上面那个的判定逻辑（每个文件一次进程，见文件头）
├── .githooks/
│   └── pre-commit         # 提交前调 check-gates.sh
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

1. **初始化技术栈**：在项目目录里运行 `npm init`、`create-next-app`、`uv init` 等。
2. **让 Agent 填写规范**：配置文件就位后，让本地 Agent 读配置文件并填写 AGENTS.md、CONTEXT.md 和 docs/（含把 Task Handoff 里的决策落成 `docs/adr/0001-*.md`）。
3. **提交**：`git add . && git commit -m "init: 项目脚手架 + 技术栈"`

生成脚本已经做过的事（不用重来）：`git init`、`core.quotepath=false`（否则中文路径会被转义成八进制）、把 `.githooks/` 挂成 pre-commit 钩子。

`core.hooksPath` 写在 `.git/config` 里，**不会随 clone 走**。clone 到别的机器后要跑一次：

```bash
git config core.hooksPath .githooks
```

完整流程见 [WORKFLOW.md](WORKFLOW.md)。

## 更新已生成的项目

脚手架改了之后，把改动推进已经生成的项目：

```bash
bash scripts/scaffold-update.sh ../my-project-name           # 预览，不写盘
bash scripts/scaffold-update.sh ../my-project-name --write   # 真的写
```

逐文件三方合并：**项目现状** × **生成时的旧模板** × **当前模板**。

| 情况 | 结果 |
|---|---|
| 项目没动过这个文件 | 直接升级到新模板 |
| 项目改过、模板没动 | 原样保留 |
| 两边都改过 | `git merge-file` 合并，合不拢就写冲突标记并返回 1 |
| 模板新增 | 加进去；项目已有同名文件则跳过，不覆盖 |
| 模板删掉 | 项目没动过就删，改过就保留并报告 |

只碰 `templates/` 里出现过的路径——`src/`、`tasks/<任务>/`、`.git/` 一概不动。脚本不做提交，写完自己看 `git diff`。

**基线（旧模板）从哪来**，按优先级：

1. `--from <sha>`；
2. 项目根 `.scaffold-version` 里记的提交（每次更新成功后写入）；
3. 都没有 → 按文件内容在脚手架历史里比对，挑最像的那个版本，并报一致率（46 个版本约 5 秒）。这是给**这个功能出现之前**生成的项目用的自举路径。

脚手架 `templates/` 有未提交改动时照样能跑（「新版」取工作区），但**不记录基线提交**——下次更新会重新比对，等你把脚手架提交了就自愈。

需要 bash 4 以上（macOS 自带的是 3.2，用 `brew install bash` 装的那个）。

## 自检

改了 `templates/` 或那两个脚本之后，跑一遍：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1
```

它校验四样东西一致：`README.md` 里那棵树、`templates/` 的实际内容、`init.sh` / `init.ps1` 实际生成的结果，以及**两个脚本产出的文件逐字节相同**（并断言每个产物与其模板「把占位符换成项目名」后逐字节相同）。同时断言"全仓库只有一棵树"——`WORKFLOW.md` 只留指针，所以模板变更只需改一处。

只比文件名集合是不够的：一个多写的换行、一次编码损坏、只有一边做了的替换，都能让两个脚本产出不同的项目而文件名完全一致。这类差异靠 SHA256 逐文件比。

### 自动跑

本仓库的 `.githooks/pre-commit` 会在提交前跑同一份**全量**检查（约 20 秒），不一致就拦下提交——这条不变量不该只靠人记得跑。被拦下就修，别习惯性 `git commit --no-verify`。

`core.hooksPath` 存在 `.git/config` 里，**不随 clone 走**。clone 到新机器后要跑一次，否则钩子根本不执行：

```bash
git config core.hooksPath .githooks
```

非 Windows 机器上没装 `pwsh` 时，钩子会跳过并提示一句（本仓库暂无 POSIX 版检查器）。

- `-SkipEndToEnd`：只跑前半段（纯文件系统对比，毫秒级）——给手动排查用，提交闸门不用它
- `-BashPath <path>`：Git Bash 不在常见位置时手动指定

## 设计原则

- 模板只写 AI 推不出来的东西。其余写成指针，指向 `docs/`
- 规则必须可检查，不写空话
- **每个流程都有退出门槛**，不是只有步骤清单。见 `docs/agents/任务分级.md`、`skills/bug-fix/SKILL.md` 的闸门 A / B
- 任务有状态（prd/plan/journal），新会话能接续
- 经验沉淀到 `docs/pitfalls.md`，决策沉淀到 `docs/adr/`，术语沉淀到 `CONTEXT.md`——都不留在聊天记录里
- 角色提示词进仓库（`docs/agents/`），不靠每次手动粘贴
- 验证是默认步骤，不是可选项
