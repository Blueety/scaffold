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
├── .scaffold-kinds        # 模板文件分类：mechanism 整份取模板 / content 按内容合并
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
| 两边都改过 | `templates/.scaffold-kinds` 标成 `mechanism` 的取模板版（本地改动备份到现场）；其余走 `git merge-file`，合不拢就写冲突标记并返回 1 |
| 模板新增 | 加进去；项目已有同名文件则跳过，不覆盖 |
| 模板删掉 | 项目没动过就删，改过就保留并报告 |

只碰 `templates/` 里出现过的路径——`src/`、`tasks/<任务>`、`.git/` 一概不动。脚本不做提交，写完自己看 `git diff`。

**目标仓库有未提交改动时拒绝写盘**（退出码 2）：脚本写的是模板路径，你改的可能是同一批文件，混在一起提交就说不清谁写了什么。先提交或 stash，或加 `--force`。

**写盘时留现场**：`<项目>/.git/scaffold-work/<时间戳>/` 里有 `MANIFEST`（这次每条动作一行）、`REVISIONS`（base / new / 基线来源），冲突文件另有 `.ours` / `.base` / `.theirs`。放在 `.git/` 下是为了不进 `git status`——不用改项目的 `.gitignore`。

**写盘后会跑一次目标仓库的闸门**，报出存量违规数与分布，并记进 `.scaffold-version`（下次对比增减）。新装进去的规则对历史文件是全红的，这个数字应该在落盘那一刻就知道，而不是等你启用钩子才发现。

**基线（旧模板）从哪来**，按优先级：

| 来源 | 怎么来的 |
|---|---|
| `--from <sha>` | 你直接指定 |
| `.scaffold-version` 的 `commit=` | 上次更新成功后写入 |
| 按内容比对 | 拿项目文件对脚手架历史，挑最像的版本，报一致率 |

第三条是给**这个功能出现之前**生成的项目用的自举路径。一致率 < 80% 时**不合并**（退出码 2）：挑错版本会把「模板演进」和「本地改写」混成同一批冲突，比不合并危险得多。三条出路：

```bash
bash scripts/scaffold-update.sh ../p --from <sha>            # 知道就指定
bash scripts/scaffold-update.sh ../p --adopt-baseline        # 只记基线，不合并
bash scripts/scaffold-update.sh ../p --adopt-baseline <sha>
bash scripts/scaffold-update.sh ../p --accept-guess          # 确认可用，硬着头皮合
```

`--adopt-baseline` 专治「脚手架历史被重写过、按内容比对不可信」——写完基线，之后每次同步都从它算起。选中的来源会记进 `baseline_source=`，下次不再重猜。

### 三类文件

| 分类 | 例子 | 「两边都改过」时 |
|---|---|---|
| `mechanism` | `docs/agents/*`、`skills/*`、`scripts/check-gates.*`、`.githooks/pre-commit`、`tasks/_template/*` | 取模板版；本地改动备份到现场。这类文件本地改了应当报上游，而不是留着 |
| `content` | `AGENTS.md`、`docs/commands.md`、`docs/pitfalls.md` | 照常三方合并；想免掉反复冲突用下面的裁决 |
| 未列出 | 其余 | 默认三方合并，和不分类时一样 |

清单在 `templates/.scaffold-kinds`，只影响更新器，闸门不读它。

### 裁决：让「本地说了算」的文件不再反复冲突

`docs/commands.md`、`docs/pitfalls.md` 这类文件，模板只给骨架、项目填满内容。它们和模板的差异是**永久分歧**，不是待合并的临时差异——不记下来，每次同步都得重新判一遍，而且模板一合并就可能把项目内容拼进去。

```bash
# 这个文件永远保留项目版本
bash scripts/scaffold-update.sh ../p --write --keep-local docs/commands.md

# 这个文件取并集：模板新增的行追加进来，本地一行不删
bash scripts/scaffold-update.sh ../p --write --union .gitignore
```

裁决记在 `.scaffold-version` 的 `decision` 段，附上当时的模板 blob。之后：

- 模板没再变 → 直接跳过，不再打扰
- 模板又变了 → `keep-local` 会提示「重新判断」（内容不动，不会偷偷合并）
- `union` 会把新增的行追加进来，本地内容一条不丢

预览时裁决同样生效（只是不落盘），所以可以先看效果再决定要不要 `--write`。

### 其他开关

| 开关 | 作用 |
|---|---|
| `--diff` | 预览时打印改动内容；跳过的同名文件也给两边行数 |
| `--json <路径>` | 结果写成 JSON（基线、来源、每文件动作、闸门数），给 CI 用 |
| `--refresh-gate-count` | 只重跑闸门、更新计数，不合并（清零常跨几个工作日） |
| `--quiet` | 不打印动作清单 |
| `--force` | 目标仓库脏也写 |

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File scripts\scaffold-update.ps1 ..\my-project --write
```

`PATH` 里的 `bash.exe` 常常是 System32 下的 WSL 桩，跑不了 Windows 路径，报错还会被控制台代码页吃成一行 `?`。这个包装器会先找 Git for Windows 自带的 bash，找不到就说清楚。脚本启动时也会自检 `find` 是不是 POSIX 的——Windows 的 `find.exe` 抢在前面时什么都不输出，会把「找不到文件」误读成别的结论。

脚手架 `templates/` 有未提交改动时照样能跑（「新版」取工作区），但**不记录基线提交**——下次更新会重新比对，等你把脚手架提交了就自愈。

需要 bash 4 以上（macOS 自带的是 3.2，用 `brew install bash` 装的那个）。

改了这个脚本要跑它自己的验收：`bash scripts/fixtures/update-test.sh`（约 200 秒，54 项断言：冲突现场、脏树、裁决、并集、基线阈值、adopt、闸门计数、机制文件、MANIFEST / JSON、`--quiet`）。闸门本身另有 `bash scripts/fixtures/gate-test.sh`（约 230 秒，67 项：规模底线含跨提交累计、空索引豁免与模板目录排除、文档断链、gitignore 与后缀解析、ADR 互链、决策锚点、模块表一格多路径、seam 措辞一致性、目标必填、纯重命名豁免、拍平归档、journal 去向）。

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
