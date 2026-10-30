# 个人项目脚手架

一键生成 Vibe Coding 开发系统所需的目录结构和规范文件。

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
│   └── check-gates.sh     # 闸门检查器（plan / journal / 切片 / [DEBUG- 残留）
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
│       └── slice.md       # 大需求拆切片时用（也承载决策条目）
└── skills/
    ├── bug-fix/
    │   └── SKILL.md       # Bug 修复流程（含闸门 A / B）
    ├── pre-review/
    │   └── SKILL.md       # 提交前双轴审查
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

## 自检

改了 `templates/` 或那两个脚本之后，跑一遍：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1
```

它校验三样东西一致：`README.md` 里那棵树、`templates/` 的实际内容、`init.sh` / `init.ps1` 实际生成的结果。同时断言"全仓库只有一棵树"——`WORKFLOW.md` 只留指针，所以模板变更只需改一处。

- `-SkipEndToEnd`：只跑前半段（纯文件系统对比，毫秒级）
- `-BashPath <path>`：Git Bash 不在常见位置时手动指定

## 设计原则

- 模板只写 AI 推不出来的东西。其余写成指针，指向 `docs/`
- 规则必须可检查，不写空话
- **每个流程都有退出门槛**，不是只有步骤清单。见 `docs/agents/任务分级.md`、`skills/bug-fix/SKILL.md` 的闸门 A / B
- 任务有状态（prd/plan/journal），新会话能接续
- 经验沉淀到 `docs/pitfalls.md`，决策沉淀到 `docs/adr/`，术语沉淀到 `CONTEXT.md`——都不留在聊天记录里
- 角色提示词进仓库（`docs/agents/`），不靠每次手动粘贴
- 验证是默认步骤，不是可选项
